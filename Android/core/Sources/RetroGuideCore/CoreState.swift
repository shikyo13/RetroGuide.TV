import Foundation
import RetroGuideKit

/// Everything the Android app knows: connected servers, their library
/// snapshots, the merged index and the lineup. Mirrors what the Apple app's
/// `AppModel` and `ServerLibrary` keep, without the UI.
actor CoreState {
    /// Token map key for the Plex account token (servers are keyed by id).
    static let plexAccountKey = "plex.account"

    var configuration: CoreConfiguration?
    var store: CoreStore?
    var accounts: [ServerAccount] = []
    /// Access tokens by server id, plus ``plexAccountKey``. Kotlin keeps them
    /// encrypted and hands them over at start; changed maps are returned to it.
    var tokens: [String: String] = [:]
    var clients: [String: any MediaServerClient] = [:]
    var snapshots: [String: LibrarySnapshot] = [:]
    var offlineServerIDs: Set<String> = []
    /// Parental controls: the policy, whether Settings are locked (the app checks
    /// the PIN), and what the policy allowed when the lineup was last built.
    var parentalPolicy = ParentalPolicy()
    var isParentalLocked = false
    var parentalAllowedItemIDs: Set<String> = []
    /// A policy draft's index for previewing custom-lineup channels, by its encoding.
    var parentalPreview: (key: Data, index: LibraryIndex)?
    /// Program reminders, soonest first, and a note about ones a lineup change removed.
    var reminders: [ProgramReminder] = []
    var reminderNote: String?
    /// The device is on a VPN, as the app last reported (see ``checkReachability(_:)``).
    var isVPNActive = false
    /// The merged library; built after ``start(_:)`` points RetroGuideKit at its data files.
    var index: LibraryIndex?
    var channels: [Channel] = []
    var customization = LineupCustomization()
    var scheduleGrid = ScheduleGrid.continuous
    var languagePreferences: LanguagePreferences?
    var progress: [String: LibraryLoadProgress] = [:]
    var curated: [ChannelDefinition] = []
    /// Built on the first search after each lineup change.
    var searchIndex: ProgramSearchIndex?

    // Personal choices, kept in the core's files.
    var viewing = ViewingPreferences()
    var trackRules = TrackRules()
    var subtitleTiming = SubtitleTimingState()
    /// RetroGuide Pro, as the app's store reports it.
    var isPro = false

    /// What the player is showing (see Tuning.swift), and the newest tune asked for.
    var playing: Playing?
    var latestTune = 0
    /// The tune whose stream playback reports describe.
    var reportedTune = 0
    let reporter = PlaybackReporter()

    // Sign-in in progress.
    var plexLinkCodes: [Int: PlexLinkCode] = [:]
    var plexCandidates: [String: PlexServerCandidate] = [:]
    var jellyfinServer: JellyfinServerInfo?
    var quickConnectCode: JellyfinQuickConnectCode?

    func requireConfiguration() throws -> CoreConfiguration {
        guard let configuration else { throw CoreError.notStarted }
        return configuration
    }

    // MARK: - Clients

    func makeClient(for account: ServerAccount, token: String, configuration: CoreConfiguration) -> any MediaServerClient {
        switch account.kind {
        case .plex:
            PlexServerClient(
                serverID: account.id,
                baseURL: account.baseURL,
                token: token,
                identity: configuration.plexIdentity,
                playback: account.playback
            )
        case .jellyfin:
            JellyfinServerClient(
                serverID: account.id,
                baseURL: account.baseURL,
                token: token,
                userID: account.userID ?? "",
                identity: configuration.jellyfinIdentity,
                playback: account.playback
            )
        }
    }

    /// Adds or replaces `account` with its access token.
    func connect(_ account: ServerAccount, token: String) throws {
        let configuration = try requireConfiguration()
        tokens[account.id] = token
        clients[account.id] = makeClient(for: account, token: token, configuration: configuration)
        // A changed server keeps its place: order is priority for duplicate copies.
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        offlineServerIDs.remove(account.id)
        store?.saveAccounts(accounts)
    }

    // MARK: - Lineup

    /// Merges the snapshots and builds the lineup from them.
    func rebuildLineup() {
        if parentalPolicy.hasTitleSelections {
            // Learn matching copies of chosen titles on every server.
            let resolved = parentalPolicy.resolvingTitles(in: ParentalTitleCatalog(snapshots: accounts.compactMap { snapshots[$0.id] }))
            if resolved != parentalPolicy {
                parentalPolicy = resolved
                store?.save(resolved, file: CoreStore.File.parental)
            }
        }
        let ordered = allowedSnapshots
        parentalAllowedItemIDs = parentalPolicy.isEnabled ? Set(ordered.flatMap { $0.items.map(\.id) }) : []
        let index = LibraryIndex(snapshots: ordered, quality: qualityByServer)
        self.index = index
        rebuildChannels()
    }

    /// Rebuilds the channels from the current index, after a lineup setting changed.
    func rebuildChannels() {
        guard let index else { return }
        let builder = LineupBuilder(curated: curated, options: LineupOptions.adapted(to: index, grid: scheduleGrid))
        channels = builder.build(index: index, customization: parentalPolicy.activeCustomization(regular: customization))
        searchIndex = nil
        if let note = reconcileReminders() { reminderNote = note }
    }

    var qualityByServer: [String: VideoQuality] {
        Dictionary(accounts.map { ($0.id, $0.playback.quality) }, uniquingKeysWith: { first, _ in first })
    }

    var visibleChannels: [Channel] {
        channels.filter { !$0.isHidden }
    }

    func channel(withID id: String) -> Channel? {
        channels.first { $0.isIdentified(by: id) }
    }
}

/// Facts about this install, given at start.
struct CoreConfiguration: Sendable {
    let plexIdentity: PlexClientIdentity
    let jellyfinIdentity: JellyfinClientIdentity
}

/// The core's files in the app's private storage.
struct CoreStore: Sendable {
    enum File {
        static let accounts = "accounts.json"
        static let customization = "customization.json"
        static let viewing = "viewing.json"
        static let trackRules = "trackRules.json"
        static let subtitleOffsets = "subtitleOffsets.json"
        static let preferences = "preferences.json"
        static let parental = "parental.json"
        static let reminders = "reminders.json"
        static let snapshots = "snapshots"
    }

    let directory: URL

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory.appending(path: File.snapshots), withIntermediateDirectories: true)
    }

    func loadAccounts() -> [ServerAccount] {
        load([ServerAccount].self, from: directory.appending(path: File.accounts)) ?? []
    }

    func saveAccounts(_ accounts: [ServerAccount]) {
        save(accounts, to: directory.appending(path: File.accounts))
    }

    func loadCustomization() -> LineupCustomization {
        load(LineupCustomization.self, from: directory.appending(path: File.customization)) ?? LineupCustomization()
    }

    func saveCustomization(_ customization: LineupCustomization) {
        save(customization, to: directory.appending(path: File.customization))
    }

    /// The cached snapshot for `serverID`, if it's in the current format.
    func loadSnapshot(serverID: String) -> LibrarySnapshot? {
        load(LibrarySnapshot.self, from: snapshotURL(serverID)).flatMap { $0.isCurrentFormat ? $0 : nil }
    }

    func saveSnapshot(_ snapshot: LibrarySnapshot) {
        save(snapshot, to: snapshotURL(snapshot.serverID))
    }

    func removeSnapshot(serverID: String) {
        try? FileManager.default.removeItem(at: snapshotURL(serverID))
    }

    func load<Value: Decodable>(_ type: Value.Type, file: String) -> Value? {
        load(type, from: directory.appending(path: file))
    }

    func save(_ value: some Encodable, file: String) {
        save(value, to: directory.appending(path: file))
    }

    private func snapshotURL(_ serverID: String) -> URL {
        let safe = serverID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? serverID
        return directory.appending(path: File.snapshots).appending(path: "\(safe).json")
    }

    private func load<Value: Decodable>(_: Value.Type, from url: URL) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? CoreCoding.decoder.decode(Value.self, from: data)
    }

    private func save(_ value: some Encodable, to url: URL) {
        guard let data = try? CoreCoding.encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
