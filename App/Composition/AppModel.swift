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

    private enum Lifecycle {
        /// How long the app can be in the background before the stream is
        /// released. Pulling Notification Center all the way down counts as
        /// the background on iPhone: a glance at it keeps the channel on.
        static let backgroundGrace: Duration = .seconds(20)
    }

    private(set) var phase: Phase = .launching
    private(set) var lineup: [Channel] = []
    /// True while channel schedules are being rebuilt (seconds with a large library).
    var isRebuildingLineup: Bool { pendingLineupRebuilds > .zero }
    private var pendingLineupRebuilds = 0
    /// Bumped by every index or lineup rebuild (and sign-out), so a slow
    /// rebuild that finishes after a newer one doesn't overwrite it.
    private var indexGeneration = 0
    private var lineupGeneration = 0
    /// Bumped on sign-out and server removal: work started before (a library
    /// download, a rebuild) must not publish into the new session.
    private var sessionGeneration = 0
    /// A refresh was asked for while one was running (settings changed,
    /// a server was added): run another with the latest settings after.
    @ObservationIgnored private var refreshPending = false
    /// The lineup build in progress, and whether another was asked for
    /// meanwhile: builds run one at a time, and the next one uses the latest
    /// settings, however many changes came in.
    @ObservationIgnored private var lineupBuild: Task<Void, Never>?
    @ObservationIgnored private var lineupBuildPending = false
    @ObservationIgnored private var searchIndexBuild: Task<Void, Never>?
    @ObservationIgnored private var isSessionStarted = false
    /// Bumped whenever a new lineup is published, so open views can refresh.
    private(set) var lineupRevision = 0
    private(set) var libraryIndex = LibraryIndex.empty
    private(set) var isRefreshing = false
    private(set) var lastRefreshed: Date?
    private(set) var refreshError: String?
    private(set) var customization: LineupCustomization
    private(set) var searchIndex = ProgramSearchIndex.empty {
        didSet { searchRevision += 1 }
    }
    /// Changes whenever ``searchIndex`` is replaced, so open searches rerun.
    private(set) var searchRevision = 0

    var preferences: UserPreferences {
        didSet { preferencesChanged(from: oldValue) }
    }

    let tuner: Tuner
    /// Saves audio and subtitle choices to the servers in the background.
    let trackSync: TrackSync
    @ObservationIgnored private let cloudTrackRules = CloudTrackRulesStore()
    let servers: ServerLibrary
    @ObservationIgnored private var nowPlaying: NowPlayingPublisher?
    let pro = ProStore()
    let plexIdentity: PlexClientIdentity

    @ObservationIgnored private let store: PreferencesStore
    @ObservationIgnored private let engine = LineupEngine()
    @ObservationIgnored private var healthTask: Task<Void, Never>?
    /// When the app went to the background, and the release of the stream
    /// waiting out ``Lifecycle/backgroundGrace``.
    @ObservationIgnored private var backgroundedAt: ContinuousClock.Instant?
    @ObservationIgnored private var backgroundRelease: Task<Void, Never>?
    @ObservationIgnored private var isRecheckingServers = false
    @ObservationIgnored private let networkMonitor = NetworkChangeMonitor()
    /// The channel to return to once a slower server brings it into the lineup,
    /// and the tune it replaced (so we don't override a channel the viewer chose).
    @ObservationIgnored private var pendingResume: (channelID: String, viewerTuneCount: Int)?
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
        self.trackSync = TrackSync { [servers] serverID in
            servers.client(for: serverID)
        }
        tuner.onChannelChanged = { [weak self] channelID in
            self?.store.lastChannelID = channelID
        }
        tuner.onServerTrouble = { [weak self] _ in
            Task { await self?.recheckServers() }
        }
        tuner.onVideoFormatChanged = { [weak self] in
            self?.updateDisplayMode()
        }
        nowPlaying = NowPlayingPublisher(actions: .init(
            play: { [weak self] in self?.tuner.resume() },
            pause: { [weak self] in self?.tuner.suspend() },
            channelUp: { [weak self] in self?.tuner.channelUp() },
            channelDown: { [weak self] in self?.tuner.channelDown() }
        ))
        tuner.onSignalChanged = { [weak self] in
            guard let self else { return }
            nowPlaying?.update(channel: tuner.channel, program: tuner.program, isPlaying: tuner.signal == .live)
        }
        tuner.languagePreferences = store.languagePreferences
        // Another device's rules (via iCloud) win over this one's older copy.
        let rules = cloudTrackRules.rules ?? store.trackRules
        store.trackRules = rules
        tuner.replaceTrackRules(rules)
        tuner.onTrackRulesChanged = { [weak self] rules, item, scope in
            self?.trackRulesChanged(rules, on: item, scope: scope)
        }
        trackSync.setCurrent(rules: rules, preferences: store.languagePreferences)
        cloudTrackRules.onChange = { [weak self] rules in
            guard let self else { return }
            store.trackRules = rules
            tuner.replaceTrackRules(rules)
            trackSync.setCurrent(rules: rules, preferences: store.languagePreferences)
        }
        cloudTrackRules.start()
    }

    // MARK: - Derived state

    var visibleChannels: [Channel] {
        lineup.filter { !$0.isHidden }
    }

    /// `channel` as it is in the current lineup (results can outlive a rebuild),
    /// or nil once it's gone.
    func currentChannel(_ channel: Channel) -> Channel? {
        lineup.first { $0.isIdentified(by: channel.id) }
    }

    /// The chosen theme, or Classic Cable when a Pro theme is chosen without Pro.
    var theme: Theme {
        let chosen = preferences.themeID
        return ThemeCatalog.theme(for: chosen.isIncludedFree || pro.isPro ? chosen : .classicCable)
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
        if DebugLaunchOptions.probesAudio {
            AudioRouteProbe.run()
            Task {
                try? await Task.sleep(for: AudioRouteProbe.playbackCheckDelay)
                AudioRouteProbe.recordPlaybackState()
            }
        }
        // The bootstrap may have reset stored settings.
        preferences = store.preferences
        customization = store.customization
        #endif
        await servers.restore()
        Task { await pro.start() }
        Task { await refreshLanguagePreferences() }
        guard servers.hasServers else {
            phase = .onboarding
            return
        }
        startConnectedSession()
        if let cachedAt = servers.oldestRefresh {
            lastRefreshed = cachedAt
            await rebuildIndexAndLineup()
            phase = .ready
            turnOn()
            // Find each server's current address before refreshing from it,
            // in case the network changed since the last session.
            await refreshConnections()
            if Date.now.timeIntervalSince(cachedAt) > Refresh.staleAfter {
                await refreshLibrary()
            }
        } else {
            await refreshLibrary()
            await refreshConnections()
        }
    }

    // MARK: - Foreground and background

    /// Releases the stream once the app has stayed in the background past
    /// the grace period (or when it comes back, if it was suspended meanwhile).
    func enteredBackground() {
        backgroundedAt = .now
        backgroundRelease?.cancel()
        backgroundRelease = Task { [weak self] in
            try? await Task.sleep(for: Lifecycle.backgroundGrace)
            guard !Task.isCancelled else { return }
            self?.tuner.suspend()
        }
    }

    /// Back from the background: the stream carries on after a short time
    /// away, and rejoins live after a longer one.
    func becameActive() {
        backgroundRelease?.cancel()
        backgroundRelease = nil
        if let backgroundedAt, ContinuousClock.now - backgroundedAt >= Lifecycle.backgroundGrace {
            tuner.suspend()
        }
        backgroundedAt = nil
        guard phase == .ready else { return }
        tuner.resume()
        Task { await refreshConnections() }
    }

    /// Re-checks server addresses right away, e.g. when the app comes back to the
    /// foreground on a different network, instead of waiting for playback to fail.
    func refreshConnections() async {
        guard phase == .ready else { return }
        await recheckServers()
    }

    func retryAfterFailure() async {
        phase = .launching
        await start()
    }

    // MARK: - Servers

    /// Adds a server chosen during onboarding or from Settings, then indexes it.
    func addServer(_ account: ServerAccount, token: String, accountToken: String?) async {
        servers.add(account, token: token, accountToken: accountToken)
        startConnectedSession()
        await refreshLibrary()
    }

    func removeServer(id: String) async {
        sessionGeneration += 1
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
        let qualityChanged = servers.qualityByServer[serverID] != playback.quality
        servers.setPlayback(playback, serverID: serverID)
        // Quality decides which copy of each item plays (and so the library
        // index); buffering only affects the stream.
        if qualityChanged {
            await rebuildIndexAndLineup()
        }
        if let channel = tuner.channel {
            tuner.tune(to: channel, isAutomatic: true)
        }
    }

    /// Changes how a server is connected to and re-tunes onto the new address.
    func updateConnection(_ connection: ServerConnectionSettings, serverID: String) async {
        await servers.setConnection(connection, serverID: serverID)
        refreshError = offlineServersMessage
        await rebuildIndexAndLineup()
        if let channel = tuner.channel {
            tuner.tune(to: channel, isAutomatic: true)
        }
    }

    func signOut() {
        sessionGeneration += 1
        refreshPending = false
        isSessionStarted = false
        networkMonitor.stop()
        healthTask?.cancel()
        tuner.powerOff()
        trackSync.cancelAll()
        tuner.replaceTrackRules(TrackRules())
        servers.removeAll()
        store.resetAll()
        indexGeneration += 1
        lineupGeneration += 1
        lineup = []
        lineupRevision += 1
        libraryIndex = .empty
        searchIndex = .empty
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
        guard !isRefreshing else {
            refreshPending = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshPending = false
            await refreshLibraryOnce()
        } while refreshPending
    }

    private func refreshLibraryOnce() async {
        let session = sessionGeneration
        guard servers.hasServers else { return }
        refreshError = nil
        let showsProgress = lineup.isEmpty
        if showsProgress {
            phase = .indexing(LibraryLoadProgress(fraction: .zero, message: "Connecting…"))
        }
        do {
            let hadFailures = try await servers.refreshAll(
                progress: { [weak self] progress in
                    guard let self, session == sessionGeneration, showsProgress, phase != .ready else { return }
                    phase = .indexing(progress)
                },
                onServerReady: { [weak self] in
                    // Go on air as soon as any server is ready; others merge in as they finish.
                    guard let self, session == sessionGeneration else { return }
                    await rebuildIndexAndLineup()
                    guard session == sessionGeneration else { return }
                    goOnAir()
                }
            )
            // Signed out or a server removed meanwhile: nothing here applies.
            guard session == sessionGeneration else { return }
            lastRefreshed = .now
            await refreshLanguagePreferences()
            refreshError = offlineServersMessage
            if hadFailures {
                await rebuildIndexAndLineup()
            }
        } catch {
            guard session == sessionGeneration else { return }
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

    /// Health checks and network-change handling for a signed-in session,
    /// started once whether the viewer signed in just now or before.
    private func startConnectedSession() {
        guard !isSessionStarted else { return }
        isSessionStarted = true
        startHealthChecks()
        networkMonitor.start { [weak self] in
            Task { await self?.refreshConnections() }
        }
    }

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
        guard !isRecheckingServers else { return }
        isRecheckingServers = true
        defer { isRecheckingServers = false }
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
        let formerIDs = lineup.first { $0.id == channelID }?.formerIDs ?? []
        updateCustomization { customization in
            if isHidden {
                customization.hiddenChannelIDs.insert(channelID)
            } else {
                // A channel hidden under an earlier id is shown again too.
                customization.hiddenChannelIDs.remove(channelID)
                customization.hiddenChannelIDs.subtract(formerIDs)
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

    /// Takes a show (or movie) off one channel; it stays on every other channel.
    func removeTitle(showID: String, fromChannel channelID: String) {
        updateCustomization { $0.removedTitles[channelID, default: []].insert(showID) }
    }

    /// Puts a show removed from a channel back on it.
    func restoreTitle(showID: String, toChannel channelID: String) {
        updateCustomization { customization in
            customization.removedTitles[channelID]?.remove(showID)
            if customization.removedTitles[channelID]?.isEmpty == true {
                customization.removedTitles[channelID] = nil
            }
        }
    }

    /// The display name of a show or movie in the library, by ``MediaItem/showID``.
    func titleName(showID: String) -> String? {
        libraryIndex.items.first { $0.showID == showID }?.headline
    }

    /// Keeps a changed choice on this device, in iCloud for the viewer's other
    /// devices, and on the servers for every app signed in to the account.
    private func trackRulesChanged(_ rules: TrackRules, on item: MediaItem, scope: TrackScope) {
        store.trackRules = rules
        cloudTrackRules.save(rules)
        trackSync.save(rules, around: item, scope: scope, among: libraryIndex.items, preferences: store.languagePreferences)
    }

    func setSimulcastLimit(_ limit: SimulcastLimit) {
        updateCustomization { $0.simulcastLimit = limit }
    }

    /// Puts every channel on one schedule order (`nil`: each channel's built-in order).
    func setOrderingForAllChannels(_ ordering: ScheduleOrdering?) {
        updateCustomization { $0.setOrderingForAllChannels(ordering) }
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
        indexGeneration += 1
        let generation = indexGeneration
        let snapshots = servers.activeSnapshots
        let index = await engine.makeIndex(from: snapshots, quality: servers.qualityByServer)
        guard generation == indexGeneration else { return }
        libraryIndex = index
        await rebuildLineup()
        #if DEBUG
        let perServer = snapshots.map { "\($0.serverName)=\($0.items.count)" }.joined(separator: " ")
        Logger(subsystem: AppIdentity.bundleIdentifier, category: "library")
            .notice("index: \(perServer, privacy: .public) merged=\(self.libraryIndex.items.count) channels=\(self.lineup.count)")
        #endif
    }

    /// Rebuilds the lineup with the current settings. A request while a build
    /// runs waits for one more build after it, which uses the latest settings.
    private func rebuildLineup() async {
        if let running = lineupBuild {
            lineupBuildPending = true
            await running.value
            return
        }
        let build = Task { [weak self] in
            guard let self else { return }
            repeat {
                lineupBuildPending = false
                await rebuildLineupOnce()
            } while lineupBuildPending
            lineupBuild = nil
        }
        lineupBuild = build
        await build.value
    }

    private func rebuildLineupOnce() async {
        lineupGeneration += 1
        let generation = lineupGeneration
        pendingLineupRebuilds += 1
        defer { pendingLineupRebuilds -= 1 }
        let built = await engine.makeLineup(index: libraryIndex, customization: customization, grid: preferences.scheduleGrid)
        guard generation == lineupGeneration else { return }
        lineup = built
        lineupRevision += 1
        tuner.setChannels(visibleChannels)
        resumeLastChannelIfAvailable()
        // Search follows on its own: nothing waits for it, least of all the first picture.
        searchIndexBuild?.cancel()
        searchIndexBuild = Task { [weak self, engine] in
            let search = await engine.makeSearchIndex(channels: built)
            guard let self, !Task.isCancelled, generation == lineupGeneration else { return }
            searchIndex = search
        }
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
        if let lastChannel = tuner.channel(withID: store.lastChannelID) {
            tuner.tune(to: lastChannel, isAutomatic: true)
        } else if let first = channels.first {
            let lastChannelID = store.lastChannelID
            tuner.tune(to: first, isAutomatic: true)
            // The last channel may come from a server that is still indexing.
            if let lastChannelID {
                pendingResume = (lastChannelID, tuner.viewerTuneCount)
            }
        }
    }

    private func resumeLastChannelIfAvailable() {
        guard let pending = pendingResume, let channel = tuner.channel(withID: pending.channelID) else { return }
        pendingResume = nil
        // Only if the viewer hasn't changed channel since we tuned the fallback.
        guard tuner.viewerTuneCount == pending.viewerTuneCount else { return }
        tuner.tune(to: channel, isAutomatic: true)
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
                    tuner.tune(to: channel, isAutomatic: true)
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

    /// Picks up changes to the account's language settings (made in Plex).
    private func refreshLanguagePreferences() async {
        guard let preferences = await servers.fetchLanguagePreferences() else { return }
        store.languagePreferences = preferences
        tuner.languagePreferences = preferences
        trackSync.setCurrent(rules: store.trackRules, preferences: preferences)
    }
}
