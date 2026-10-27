import Foundation
import RetroGuideKit

// MARK: - Start

struct StartParams: Decodable, Sendable {
    /// Where the core keeps its files (the app's private storage).
    let filesDirectory: String
    /// Where the Kit's data files were copied from the app's assets.
    let resourcesDirectory: String
    /// A random id made once per install, as on Apple platforms.
    let installID: String
    let deviceName: String
    let appVersion: String
    let osVersion: String
    let tokens: [String: String]
}

struct StartResult: Encodable, Sendable {
    let servers: [ServerInfo]
    let channelCount: Int
}

struct ServerInfo: Encodable, Sendable {
    let id: String
    let name: String
    let kind: String
    let address: String
    let isOnline: Bool
}

/// Answers that change the stored tokens hand the whole map back to Kotlin to keep.
struct ServersChange: Encodable, Sendable {
    let servers: [ServerInfo]
    let tokens: [String: String]
}

extension CoreState {
    private enum Identity {
        static let product = "RetroGuide.TV"
        static let platform = "Android"
        static let device = "Android TV"
    }

    func start(_ params: StartParams) throws -> StartResult {
        KitResources.use(directory: URL(fileURLWithPath: params.resourcesDirectory))
        let configuration = CoreConfiguration(
            plexIdentity: PlexClientIdentity(
                clientIdentifier: params.installID,
                product: Identity.product,
                version: params.appVersion,
                platform: Identity.platform,
                platformVersion: params.osVersion,
                device: Identity.device,
                deviceName: params.deviceName
            ),
            jellyfinIdentity: JellyfinClientIdentity(
                deviceID: params.installID,
                deviceName: params.deviceName,
                client: Identity.product,
                version: params.appVersion
            )
        )
        self.configuration = configuration
        let store = CoreStore(directory: URL(fileURLWithPath: params.filesDirectory))
        self.store = store
        curated = try ChannelCatalog.curated()
        tokens = params.tokens
        customization = store.loadCustomization()
        accounts = store.loadAccounts().filter { params.tokens[$0.id] != nil }
        for account in accounts {
            if let token = tokens[account.id] {
                clients[account.id] = makeClient(for: account, token: token, configuration: configuration)
            }
            snapshots[account.id] = store.loadSnapshot(serverID: account.id)
        }
        if !snapshots.isEmpty {
            rebuildLineup()
        }
        return StartResult(servers: serverList(), channelCount: visibleChannels.count)
    }

    func serverList() -> [ServerInfo] {
        accounts.map { account in
            ServerInfo(
                id: account.id,
                name: account.name,
                kind: account.kind.rawValue,
                address: account.baseURL.host() ?? account.baseURL.absoluteString,
                isOnline: !offlineServerIDs.contains(account.id)
            )
        }
    }

    func removeServer(_ serverID: String) -> ServersChange {
        accounts.removeAll { $0.id == serverID }
        clients[serverID] = nil
        tokens[serverID] = nil
        snapshots[serverID] = nil
        store?.saveAccounts(accounts)
        store?.removeSnapshot(serverID: serverID)
        if accounts.isEmpty {
            tokens[Self.plexAccountKey] = nil
        }
        rebuildLineup()
        return ServersChange(servers: serverList(), tokens: tokens)
    }

    func changes() -> ServersChange {
        ServersChange(servers: serverList(), tokens: tokens)
    }
}

// MARK: - Development

/// A server added directly with a known address and token, as the Apple app's
/// DEBUG bootstrap does for QA. The Android app only sends it from debug builds.
struct DevelopmentServerParams: Decodable, Sendable {
    let id: String
    let kind: String
    let name: String
    let address: String
    let token: String
    let userID: String?
    /// The Plex account token, for the account's language settings.
    let accountToken: String?
}

extension CoreState {
    func addDevelopmentServer(_ params: DevelopmentServerParams) throws -> ServersChange {
        guard let kind = ServerKind(rawValue: params.kind), let url = URL(string: params.address) else { throw CoreError.unknownServer }
        try connect(ServerAccount(id: params.id, kind: kind, name: params.name, baseURL: url, userID: params.userID), token: params.token)
        if let accountToken = params.accountToken {
            tokens[Self.plexAccountKey] = accountToken
        }
        return changes()
    }
}

// MARK: - Libraries

struct ServerParams: Decodable, Sendable {
    let serverID: String
}

struct LibraryInfo: Encodable, Sendable {
    let id: String
    let title: String
    let kind: String
    let isSelected: Bool
}

struct LibrarySelectionParams: Decodable, Sendable {
    let serverID: String
    /// Empty selects every library, including ones added later.
    let libraryIDs: [String]
}

extension CoreState {
    func libraries(serverID: String) async throws -> [LibraryInfo] {
        guard let client = clients[serverID], let account = accounts.first(where: { $0.id == serverID }) else {
            throw CoreError.unknownServer
        }
        return try await client.fetchLibraries().filter(\.isSchedulable).map { library in
            LibraryInfo(
                id: library.id,
                title: library.title,
                kind: library.kind.rawValue,
                isSelected: account.selectedLibraryIDs.isEmpty || account.selectedLibraryIDs.contains(library.id)
            )
        }
    }

    func selectLibraries(_ params: LibrarySelectionParams) -> Done {
        if let index = accounts.firstIndex(where: { $0.id == params.serverID }) {
            accounts[index].selectedLibraryIDs = Set(params.libraryIDs)
            store?.saveAccounts(accounts)
        }
        return Done()
    }
}

// MARK: - Plex

struct LinkCodeInfo: Encodable, Sendable {
    let id: Int
    let code: String
    let url: String
}

struct PlexLinkParams: Decodable, Sendable {
    let id: Int
}

struct LinkStatus: Encodable, Sendable {
    let isLinked: Bool
}

struct PlexServerOption: Encodable, Sendable {
    let id: String
    let name: String
    let isOwned: Bool
}

struct PlexAddParams: Decodable, Sendable {
    let ids: [String]
}

extension CoreState {
    private func plexAccounts() throws -> PlexAccountService {
        PlexAccountService(identity: try requireConfiguration().plexIdentity)
    }

    func plexLinkCode() async throws -> LinkCodeInfo {
        let code = try await plexAccounts().createLinkCode()
        plexLinkCodes[code.id] = code
        return LinkCodeInfo(id: code.id, code: code.code, url: code.linkURL.absoluteString)
    }

    /// Whether the code has been entered at plex.tv/link yet.
    func checkPlexLink(id: Int) async throws -> LinkStatus {
        guard let code = plexLinkCodes[id] else { throw CoreError.notLinked }
        guard let token = try await plexAccounts().token(for: code) else { return LinkStatus(isLinked: false) }
        tokens[Self.plexAccountKey] = token
        plexLinkCodes[id] = nil
        return LinkStatus(isLinked: true)
    }

    func plexServers() async throws -> [PlexServerOption] {
        guard let accountToken = tokens[Self.plexAccountKey] else { throw CoreError.notLinked }
        let candidates = try await plexAccounts().servers(accountToken: accountToken)
        plexCandidates = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let connected = Set(accounts.map(\.id))
        return candidates.filter { !connected.contains($0.id) }.map { PlexServerOption(id: $0.id, name: $0.name, isOwned: $0.isOwned) }
    }

    /// Finds a working address for each chosen server and connects it.
    func addPlexServers(ids: [String]) async throws -> ServersChange {
        let resolver = PlexConnectionResolver(identity: try requireConfiguration().plexIdentity)
        var lastError: Error?
        for id in ids {
            guard let candidate = plexCandidates[id] else { continue }
            do {
                let url = try await resolver.resolve(candidate)
                try connect(ServerAccount(id: candidate.id, kind: .plex, name: candidate.name, baseURL: url), token: candidate.accessToken)
            } catch {
                lastError = error
            }
        }
        if accounts.isEmpty, let lastError { throw lastError }
        return changes()
    }
}

// MARK: - Jellyfin

struct JellyfinFindParams: Decodable, Sendable {
    let address: String
}

struct JellyfinServerOption: Encodable, Sendable {
    let id: String
    let name: String
    let address: String
    let hasQuickConnect: Bool
}

struct QuickConnectInfo: Encodable, Sendable {
    let code: String
}

struct QuickConnectStatus: Encodable, Sendable {
    let isApproved: Bool
    let change: ServersChange?
}

struct JellyfinSignInParams: Decodable, Sendable {
    let username: String
    let password: String
}

enum JellyfinError: LocalizedError {
    case notFound
    case noServer

    var errorDescription: String? {
        switch self {
        case .notFound: "No Jellyfin server answered securely. Use an HTTPS address with a trusted certificate."
        case .noServer: "Find a Jellyfin server first."
        }
    }
}

extension CoreState {
    private func jellyfinAccounts() throws -> JellyfinAccountService {
        JellyfinAccountService(identity: try requireConfiguration().jellyfinIdentity)
    }

    func findJellyfin(address: String) async throws -> JellyfinServerOption {
        let service = try jellyfinAccounts()
        guard let server = await service.findServer(at: address) else { throw JellyfinError.notFound }
        jellyfinServer = server
        quickConnectCode = nil
        return JellyfinServerOption(
            id: server.id,
            name: server.name,
            address: server.baseURL.absoluteString,
            hasQuickConnect: await service.isQuickConnectEnabled(on: server)
        )
    }

    func startQuickConnect() async throws -> QuickConnectInfo {
        guard let server = jellyfinServer else { throw JellyfinError.noServer }
        let code = try await jellyfinAccounts().startQuickConnect(on: server)
        quickConnectCode = code
        return QuickConnectInfo(code: code.code)
    }

    func checkQuickConnect() async throws -> QuickConnectStatus {
        guard let server = jellyfinServer, let code = quickConnectCode else { throw JellyfinError.noServer }
        guard let session = try await jellyfinAccounts().session(for: code, on: server) else {
            return QuickConnectStatus(isApproved: false, change: nil)
        }
        quickConnectCode = nil
        return QuickConnectStatus(isApproved: true, change: try addJellyfin(server, session: session))
    }

    func signInJellyfin(_ params: JellyfinSignInParams) async throws -> ServersChange {
        guard let server = jellyfinServer else { throw JellyfinError.noServer }
        let session = try await jellyfinAccounts().signIn(on: server, username: params.username, password: params.password)
        return try addJellyfin(server, session: session)
    }

    private func addJellyfin(_ server: JellyfinServerInfo, session: JellyfinSession) throws -> ServersChange {
        let account = ServerAccount(id: server.id, kind: .jellyfin, name: server.name, baseURL: server.baseURL, userID: session.userID)
        try connect(account, token: session.accessToken)
        return changes()
    }
}
