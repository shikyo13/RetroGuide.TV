import Foundation
import Observation
import RetroGuideKit

/// Root application state: connected servers, the library index, the channel
/// lineup, preferences and the tuner. Views observe it; features call its intents.
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
    }

    private(set) var phase: Phase = .launching
    private(set) var accounts: [ServerAccount] = []
    private(set) var lineup: [Channel] = []
    private(set) var libraryIndex = LibraryIndex.empty
    private(set) var artworkResolver = ArtworkResolver.unavailable
    private(set) var isRefreshing = false
    private(set) var lastRefreshed: Date?
    private(set) var refreshError: String?
    private(set) var customization: LineupCustomization

    var preferences: UserPreferences {
        didSet { preferencesChanged(from: oldValue) }
    }

    let tuner: Tuner
    let plexIdentity: PlexClientIdentity

    @ObservationIgnored private let store: PreferencesStore
    @ObservationIgnored private let snapshotStore: LibrarySnapshotStore
    @ObservationIgnored private let registry: ServerRegistry
    @ObservationIgnored private let engine = LineupEngine()
    @ObservationIgnored private var snapshots: [String: LibrarySnapshot] = [:]

    init(store: PreferencesStore = PreferencesStore(), snapshotStore: LibrarySnapshotStore = LibrarySnapshotStore()) {
        self.store = store
        self.snapshotStore = snapshotStore
        self.preferences = store.preferences
        self.customization = store.customization
        let identity = AppIdentity.plexIdentity(clientIdentifier: store.plexClientIdentifier)
        self.plexIdentity = identity
        let registry = ServerRegistry(keychain: KeychainStore(), plexIdentity: identity)
        self.registry = registry
        self.tuner = Tuner(engineKind: store.preferences.playerEngine) { [registry] serverID in
            registry.client(for: serverID)
        }
        tuner.onChannelChanged = { [weak self] channelID in
            self?.preferences.lastChannelID = channelID
        }
    }

    // MARK: - Derived state

    var visibleChannels: [Channel] {
        lineup.filter { !$0.isHidden }
    }

    var theme: Theme {
        ThemeCatalog.theme(for: preferences.themeID)
    }

    func client(for serverID: String) -> (any MediaServerClient)? {
        registry.client(for: serverID)
    }

    func previewItems(for rule: ChannelRule) -> [MediaItem] {
        engine.preview(rule: rule, in: libraryIndex)
    }

    // MARK: - Launch

    func start() async {
        guard phase == .launching else { return }
        #if DEBUG
        await DebugBootstrap.seedAccountIfRequested(store: store, keychain: KeychainStore(), identity: plexIdentity)
        #endif
        accounts = store.accounts
        let missingTokens = registry.connect(accounts)
        accounts.removeAll { account in missingTokens.contains { $0.id == account.id } }
        artworkResolver = registry.artworkResolver
        guard !accounts.isEmpty else {
            phase = .onboarding
            return
        }
        for account in accounts {
            if let snapshot = await snapshotStore.load(serverID: account.id) {
                snapshots[account.id] = snapshot
            }
        }
        if snapshots.count == accounts.count {
            lastRefreshed = snapshots.values.map(\.refreshedAt).min()
            await rebuildIndexAndLineup()
            phase = .ready
            turnOn()
            if let lastRefreshed, Date.now.timeIntervalSince(lastRefreshed) > Refresh.staleAfter {
                await refreshLibrary()
            }
        } else {
            await refreshLibrary()
        }
    }

    // MARK: - Servers

    /// Called by onboarding once the user has signed in and chosen libraries.
    func addServer(_ account: ServerAccount, token: String) async {
        registry.add(account, token: token)
        artworkResolver = registry.artworkResolver
        accounts.removeAll { $0.id == account.id }
        accounts.append(account)
        store.accounts = accounts
        await refreshLibrary()
    }

    func updateLibrarySelection(serverID: String, libraryIDs: Set<String>) async {
        guard let index = accounts.firstIndex(where: { $0.id == serverID }) else { return }
        accounts[index].selectedLibraryIDs = libraryIDs
        store.accounts = accounts
        await refreshLibrary()
    }

    func libraries(forServer serverID: String) async throws -> [MediaLibrary] {
        guard let client = registry.client(for: serverID) else { return [] }
        return try await client.fetchLibraries().filter(\.isSchedulable)
    }

    func signOut() {
        tuner.powerOff()
        for account in accounts {
            registry.remove(serverID: account.id)
            snapshotStore.remove(serverID: account.id)
        }
        store.resetAll()
        accounts = []
        snapshots = [:]
        lineup = []
        libraryIndex = .empty
        customization = LineupCustomization()
        preferences = UserPreferences()
        artworkResolver = registry.artworkResolver
        phase = .onboarding
    }

    // MARK: - Library

    /// Re-downloads every server's library. Shows full-screen progress only when
    /// there is nothing to watch yet; otherwise refreshes quietly.
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
            for account in accounts {
                snapshots[account.id] = try await downloadSnapshot(for: account, showsProgress: showsProgress)
            }
            lastRefreshed = .now
            await rebuildIndexAndLineup()
            if phase != .ready {
                phase = .ready
                turnOn()
            }
        } catch {
            refreshError = error.localizedDescription
            if showsProgress {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func retryAfterFailure() async {
        phase = .launching
        await start()
    }

    private func downloadSnapshot(for account: ServerAccount, showsProgress: Bool) async throws -> LibrarySnapshot {
        guard let client = registry.client(for: account.id) else {
            throw HTTPError.unauthorized
        }
        let libraries = try await client.fetchLibraries().filter {
            $0.isSchedulable && (account.selectedLibraryIDs.isEmpty || account.selectedLibraryIDs.contains($0.id))
        }
        let items = try await client.fetchItems(in: libraries) { [weak self] progress in
            guard showsProgress else { return }
            Task { @MainActor in
                self?.phase = .indexing(progress)
            }
        }
        let snapshot = LibrarySnapshot(serverID: account.id, libraries: libraries, items: items)
        await snapshotStore.save(snapshot)
        return snapshot
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
        libraryIndex = await engine.makeIndex(from: Array(snapshots.values))
        await rebuildLineup()
    }

    private func rebuildLineup() async {
        lineup = await engine.makeLineup(index: libraryIndex, customization: customization, grid: preferences.scheduleGrid)
        tuner.setChannels(visibleChannels)
    }

    /// Powers the "TV" on to the last watched channel (or the first one).
    private func turnOn() {
        let channels = visibleChannels
        tuner.setChannels(channels)
        guard tuner.channel == nil,
              let channel = tuner.channel(withID: preferences.lastChannelID) ?? channels.first
        else { return }
        tuner.tune(to: channel)
    }

    private func preferencesChanged(from old: UserPreferences) {
        store.preferences = preferences
        if old.playerEngine != preferences.playerEngine {
            tuner.useEngine(preferences.playerEngine)
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
}
