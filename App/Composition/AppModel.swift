import Foundation
import Observation
import OSLog
import RetroGuideKit

/// Root application state: the channel lineup, preferences and the tuner.
/// Servers and their libraries are managed by ``ServerLibrary``.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case launching
        case onboarding
        case indexing(LibraryLoadProgress)
        case ready
        case failed(String)
    }

    private enum Refresh {
        /// Re-index automatically in the background when the cache is older than this.
        static let staleAfter: TimeInterval = 6 * ScheduleConstants.secondsPerHour
        /// How often server reachability is re-checked while the app is open.
        static let healthCheckInterval: Duration = .seconds(10 * 60)
    }

    private(set) var phase: Phase = .launching
    private(set) var lineup: [Channel] = []
    private(set) var libraryIndex = LibraryIndex.empty
    private(set) var isRefreshing = false
    private(set) var lastRefreshed: Date?
    private(set) var refreshError: String?
    private(set) var customization: LineupCustomization
    private(set) var searchIndex = ProgramSearchIndex.empty

    var preferences: UserPreferences {
        didSet { preferencesChanged(from: oldValue) }
    }

    let tuner: Tuner
    let servers: ServerLibrary
    let plexIdentity: PlexClientIdentity

    @ObservationIgnored private let store: PreferencesStore
    @ObservationIgnored private let engine = LineupEngine()
    @ObservationIgnored private var healthTask: Task<Void, Never>?
    /// The channel to return to once a slower server brings it into the lineup,
    /// and the tune it replaced (so we don't override a channel the viewer chose).
    @ObservationIgnored private var pendingResume: (channelID: String, tuneGeneration: Int)?
    #if os(tvOS)
    @ObservationIgnored private let displayMode = DisplayModeController()
    #endif

    init(store: PreferencesStore = PreferencesStore(), snapshotStore: LibrarySnapshotStore = LibrarySnapshotStore()) {
        self.store = store
        self.preferences = store.preferences
        self.customization = store.customization
        let identity = AppIdentity.plexIdentity(clientIdentifier: store.plexClientIdentifier)
        self.plexIdentity = identity
        let servers = ServerLibrary(store: store, snapshotStore: snapshotStore, keychain: KeychainStore(), identity: identity)
        self.servers = servers
        self.tuner = Tuner(engineKind: store.preferences.playerEngine) { [servers] serverID in
            servers.client(for: serverID)
        }
        tuner.onChannelChanged = { [weak self] channelID in
            self?.preferences.lastChannelID = channelID
        }
        tuner.onServerTrouble = { [weak self] _ in
            Task { await self?.recheckServers() }
        }
        tuner.onVideoFormatChanged = { [weak self] in
            self?.updateDisplayMode()
        }
    }

    // MARK: - Derived state

    var visibleChannels: [Channel] {
        lineup.filter { !$0.isHidden }
    }

    var theme: Theme {
        ThemeCatalog.theme(for: preferences.themeID)
    }

    var artworkResolver: ArtworkResolver {
        servers.artworkResolver
    }

    func previewItems(for rule: ChannelRule) -> [MediaItem] {
        engine.preview(rule: rule, in: libraryIndex)
    }

    // MARK: - Launch

    func start() async {
        guard phase == .launching else { return }
        #if DEBUG
        await DebugBootstrap.seedAccountIfRequested(store: store, keychain: KeychainStore(), identity: plexIdentity)
        // The bootstrap may have reset stored settings.
        preferences = store.preferences
        customization = store.customization
        #endif
        await servers.restore()
        guard servers.hasServers else {
            phase = .onboarding
            return
        }
        startHealthChecks()
        if let cachedAt = servers.oldestRefresh {
            lastRefreshed = cachedAt
            await rebuildIndexAndLineup()
            phase = .ready
            turnOn()
            if Date.now.timeIntervalSince(cachedAt) > Refresh.staleAfter {
                await refreshLibrary()
            }
        } else {
            await refreshLibrary()
        }
    }

    func retryAfterFailure() async {
        phase = .launching
        await start()
    }

    // MARK: - Servers

    /// Adds a server chosen during onboarding or from Settings, then indexes it.
    func addServer(_ account: ServerAccount, token: String, accountToken: String?) async {
        servers.add(account, token: token, accountToken: accountToken)
        startHealthChecks()
        await refreshLibrary()
    }

    func removeServer(id: String) async {
        servers.remove(serverID: id)
        guard servers.hasServers else {
            signOut()
            return
        }
        await rebuildIndexAndLineup()
    }

    func updateLibrarySelection(serverID: String, libraryIDs: Set<String>) async {
        servers.setSelectedLibraries(libraryIDs, serverID: serverID)
        await refreshLibrary()
    }

    /// Applies a server's quality/buffering settings and rejoins the current channel.
    func updatePlayback(_ playback: ServerPlaybackSettings, serverID: String) async {
        servers.setPlayback(playback, serverID: serverID)
        await rebuildIndexAndLineup()
        if let channel = tuner.channel {
            tuner.tune(to: channel)
        }
    }

    func signOut() {
        healthTask?.cancel()
        tuner.powerOff()
        servers.removeAll()
        store.resetAll()
        lineup = []
        libraryIndex = .empty
        customization = LineupCustomization()
        preferences = UserPreferences()
        #if os(tvOS)
        displayMode.reset()
        #endif
        phase = .onboarding
    }

    // MARK: - Library

    /// Re-indexes every server. Shows full-screen progress only when there is
    /// nothing to watch yet; otherwise refreshes quietly.
    func refreshLibrary() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshError = nil
        defer { isRefreshing = false }
        let showsProgress = lineup.isEmpty
        if showsProgress {
            phase = .indexing(LibraryLoadProgress(fraction: .zero, message: "Connecting…"))
        }
        do {
            let hadFailures = try await servers.refreshAll(
                progress: { [weak self] progress in
                    guard let self, showsProgress, phase != .ready else { return }
                    phase = .indexing(progress)
                },
                onServerReady: { [weak self] in
                    // Go on air as soon as any server is ready; others merge in as they finish.
                    await self?.rebuildIndexAndLineup()
                    self?.goOnAir()
                }
            )
            lastRefreshed = .now
            refreshError = offlineServersMessage
            if hadFailures {
                await rebuildIndexAndLineup()
            }
        } catch {
            refreshError = error.localizedDescription
            if showsProgress {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private var offlineServersMessage: String? {
        let offline = servers.accounts.filter { servers.status[$0.id] == .offline }.map(\.name)
        return offline.isEmpty ? nil : "Offline: \(offline.joined(separator: ", "))"
    }

    // MARK: - Reachability

    private func startHealthChecks() {
        healthTask?.cancel()
        healthTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Refresh.healthCheckInterval)
                await self?.recheckServers()
            }
        }
    }

    /// Re-probes servers; if one went offline or came back, the lineup is rebuilt
    /// so channels only air content that can actually play.
    private func recheckServers() async {
        guard await servers.checkReachability() else { return }
        refreshError = offlineServersMessage
        await rebuildIndexAndLineup()
    }

    // MARK: - Lineup

    func updateCustomization(_ change: (inout LineupCustomization) -> Void) {
        change(&customization)
        store.customization = customization
        Task { await rebuildLineup() }
    }

    func setHidden(_ isHidden: Bool, channelID: String) {
        updateCustomization { customization in
            if isHidden {
                customization.hiddenChannelIDs.insert(channelID)
            } else {
                customization.hiddenChannelIDs.remove(channelID)
            }
        }
    }

    func setSource(_ source: ChannelSource, enabled: Bool) {
        updateCustomization { customization in
            if enabled {
                customization.disabledSources.remove(source)
            } else {
                customization.disabledSources.insert(source)
            }
        }
    }

    func setOrdering(_ ordering: ScheduleOrdering, for definition: ChannelDefinition) {
        updateCustomization { customization in
            if let index = customization.customChannels.firstIndex(where: { $0.id == definition.id }) {
                customization.customChannels[index].ordering = ordering
            } else {
                customization.orderingOverrides[definition.id] = ordering
            }
        }
    }

    /// Adds a new custom channel or replaces an existing one with the same id.
    func saveCustomChannel(_ definition: ChannelDefinition) {
        updateCustomization { customization in
            if let index = customization.customChannels.firstIndex(where: { $0.id == definition.id }) {
                customization.customChannels[index] = definition
            } else {
                customization.customChannels.append(definition)
            }
        }
    }

    func deleteCustomChannel(id: String) {
        updateCustomization { customization in
            customization.customChannels.removeAll { $0.id == id }
            customization.hiddenChannelIDs.remove(id)
        }
    }

    private func rebuildIndexAndLineup() async {
        let snapshots = servers.activeSnapshots
        libraryIndex = await engine.makeIndex(from: snapshots, quality: servers.qualityByServer)
        await rebuildLineup()
        #if DEBUG
        let perServer = snapshots.map { "\($0.serverName)=\($0.items.count)" }.joined(separator: " ")
        Logger(subsystem: AppIdentity.bundleIdentifier, category: "library")
            .notice("index: \(perServer, privacy: .public) merged=\(self.libraryIndex.items.count) channels=\(self.lineup.count)")
        #endif
    }

    private func rebuildLineup() async {
        lineup = await engine.makeLineup(index: libraryIndex, customization: customization, grid: preferences.scheduleGrid)
        tuner.setChannels(visibleChannels)
        resumeLastChannelIfAvailable()
        searchIndex = await engine.makeSearchIndex(channels: lineup)
    }

    private func goOnAir() {
        guard phase != .ready else { return }
        phase = .ready
        turnOn()
    }

    /// Powers the "TV" on to the last watched channel (or the first one).
    private func turnOn() {
        let channels = visibleChannels
        tuner.setChannels(channels)
        guard tuner.channel == nil else { return }
        if let lastChannel = tuner.channel(withID: preferences.lastChannelID) {
            tuner.tune(to: lastChannel)
        } else if let first = channels.first {
            let lastChannelID = preferences.lastChannelID
            tuner.tune(to: first)
            // The last channel may come from a server that is still indexing.
            if let lastChannelID {
                pendingResume = (lastChannelID, tuner.tuneGeneration)
            }
        }
    }

    private func resumeLastChannelIfAvailable() {
        guard let pending = pendingResume, let channel = tuner.channel(withID: pending.channelID) else { return }
        pendingResume = nil
        // Only if the viewer hasn't changed channel since we tuned the fallback.
        guard tuner.tuneGeneration == pending.tuneGeneration else { return }
        tuner.tune(to: channel)
    }

    private func preferencesChanged(from old: UserPreferences) {
        store.preferences = preferences
        if old.playerEngine != preferences.playerEngine {
            tuner.useEngine(preferences.playerEngine)
        }
        if old.displayMatching != preferences.displayMatching {
            updateDisplayMode()
        }
        if old.scheduleGrid != preferences.scheduleGrid {
            Task {
                await rebuildLineup()
                if let channel = tuner.channel {
                    tuner.tune(to: channel)
                }
            }
        }
    }

    /// Apple TV: switches the TV's output mode for the playing video and tells
    /// the player whether to output HDR. iPhone and iPad handle HDR on their own.
    private func updateDisplayMode() {
        #if os(tvOS)
        let prefersHDROutput = displayMode.update(format: tuner.videoFormat, matching: preferences.displayMatching)
        tuner.engine.setPrefersHDROutput(prefersHDROutput)
        #endif
    }
}
