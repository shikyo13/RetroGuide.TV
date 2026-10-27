import Foundation
import RetroGuideKit

/// One server in Settings › Servers.
struct ServerDetail: Encodable, Sendable {
    let id: String
    let name: String
    let kind: String
    let kindName: String
    let isOffline: Bool
    /// "Connected through: Home network (192.168.1.20)", or why it can't be reached.
    let status: String
    let quality: String
    let qualities: [LineupSettings.Described]
    let extraBuffering: Bool
    let connection: String
    let connections: [LineupSettings.Described]
    /// The typed custom address, as typed (Plex).
    let customAddress: String?
    /// The server's address (Jellyfin, whose address is its whole connection setting).
    let address: String
}

struct PlaybackParams: Decodable, Sendable {
    let serverID: String
    let quality: String?
    let extraBuffering: Bool?
}

struct ConnectionParams: Decodable, Sendable {
    let serverID: String
    /// A ``ConnectionPreference``.
    let preference: String
    /// What the viewer typed, for a custom address.
    let address: String?
}

struct AddressParams: Decodable, Sendable {
    let serverID: String
    let address: String
}

/// The answer to a connection change: the server as it is now, and a message when it went wrong.
struct ConnectionResult: Encodable, Sendable {
    let server: ServerDetail
    let message: String?
}

struct ReachabilityParams: Decodable, Sendable {
    /// The device is on a VPN (addresses reached over it are preferred then).
    let isVPNActive: Bool
}

struct ReachabilityResult: Encodable, Sendable {
    /// Whether any server came back or dropped out (the lineup was rebuilt).
    let changed: Bool
}

extension CoreState {
    private enum PlexDirect {
        static let suffix = ".plex.direct"
    }

    func serverDetail(_ params: ServerParams) throws -> ServerDetail {
        guard let account = accounts.first(where: { $0.id == params.serverID }) else { throw CoreError.unknownServer }
        let isOffline = offlineServerIDs.contains(account.id)
        return ServerDetail(
            id: account.id,
            name: account.name,
            kind: account.kind.rawValue,
            kindName: account.kind.displayName,
            isOffline: isOffline,
            status: isOffline
                ? "This server can't be reached right now. Its programs are left out of the guide until it's back."
                : "Connected through: \(ConnectionRoute(account.baseURL).displayName) (\(Self.shortAddress(account.baseURL))).",
            quality: account.playback.quality.rawValue,
            qualities: VideoQuality.allCases.map { LineupSettings.Described(id: $0.rawValue, title: $0.displayName, detail: $0.explanation) },
            extraBuffering: account.playback.extraBuffering,
            connection: account.connection.preference.rawValue,
            connections: ConnectionPreference.allCases.map { LineupSettings.Described(id: $0.rawValue, title: $0.displayName, detail: $0.explanation) },
            customAddress: account.connection.customAddress.map { Self.shortAddress($0) + ($0.port.map { ":\($0)" } ?? "") },
            address: account.baseURL.absoluteString
        )
    }

    /// Changes a server's quality or buffering. Quality decides which copy of
    /// each item plays, so the library index is rebuilt for it.
    func setPlayback(_ params: PlaybackParams) throws -> ServerDetail {
        guard let index = accounts.firstIndex(where: { $0.id == params.serverID }) else { throw CoreError.unknownServer }
        let previousQuality = accounts[index].playback.quality
        if let quality = params.quality.flatMap(VideoQuality.init(rawValue:)) { accounts[index].playback.quality = quality }
        if let extraBuffering = params.extraBuffering { accounts[index].playback.extraBuffering = extraBuffering }
        try reconnect(accounts[index])
        if accounts[index].playback.quality != previousQuality { rebuildLineup() }
        return try serverDetail(ServerParams(serverID: params.serverID))
    }

    /// Saves how a Plex server is reached and switches to the best address under it.
    func setConnection(_ params: ConnectionParams) async throws -> ConnectionResult {
        guard let index = accounts.firstIndex(where: { $0.id == params.serverID }),
              let preference = ConnectionPreference(rawValue: params.preference)
        else { throw CoreError.unknownServer }
        var connection = accounts[index].connection
        connection.preference = preference
        if preference == .custom {
            if let typed = params.address {
                guard let url = PlexCustomAddress.url(from: typed, serverURL: accounts[index].baseURL) else {
                    return ConnectionResult(server: try serverDetail(ServerParams(serverID: params.serverID)), message: "Enter a valid HTTPS server address.")
                }
                connection.customAddress = url
            } else if connection.customAddress == nil {
                // Wait for an address before switching anything.
                accounts[index].connection = connection
                store?.saveAccounts(accounts)
                return ConnectionResult(server: try serverDetail(ServerParams(serverID: params.serverID)), message: nil)
            }
        }
        accounts[index].connection = connection
        store?.saveAccounts(accounts)
        let account = accounts[index]
        if let url = await relocatePlexServer(account, isVPNActive: isVPNActive), url != account.baseURL {
            try move(account, to: url)
        }
        let reachable = await clients[account.id]?.isReachable() ?? false
        setOffline(!reachable, serverID: account.id)
        rebuildLineup()
        return ConnectionResult(
            server: try serverDetail(ServerParams(serverID: params.serverID)),
            message: reachable ? nil : "Couldn't reach the server with this setting."
        )
    }

    /// Moves a Jellyfin server to a typed address, if the same server answers there.
    func changeJellyfinAddress(_ params: AddressParams) async throws -> ConnectionResult {
        guard let account = accounts.first(where: { $0.id == params.serverID }) else { throw CoreError.unknownServer }
        let found = await JellyfinAccountService(identity: try requireConfiguration().jellyfinIdentity).findServer(at: params.address)
        guard let server = found else {
            return ConnectionResult(server: try serverDetail(ServerParams(serverID: account.id)),
                message: "No Jellyfin server answered securely there. Use an HTTPS address with a trusted certificate.")
        }
        guard server.isServer(account.id) else {
            return ConnectionResult(server: try serverDetail(ServerParams(serverID: account.id)),
                message: "That address is \(server.name), a different server. Add it from Servers instead.")
        }
        try move(account, to: server.baseURL)
        setOffline(false, serverID: account.id)
        rebuildLineup()
        return ConnectionResult(server: try serverDetail(ServerParams(serverID: account.id)), message: nil)
    }

    /// Probes every server (the Apple app's health check). Unreachable Plex
    /// servers are looked up again through the Plex account, and servers on a
    /// worse address switch back when the better one answers.
    func checkReachability(_ params: ReachabilityParams) async -> ReachabilityResult {
        isVPNActive = params.isVPNActive
        var changed = false
        for account in accounts {
            let reachable = await isReachable(account, isVPNActive: params.isVPNActive)
            if reachable == offlineServerIDs.contains(account.id) {
                setOffline(!reachable, serverID: account.id)
                changed = true
            }
        }
        if changed { rebuildLineup() }
        return ReachabilityResult(changed: changed)
    }

    private func isReachable(_ original: ServerAccount, isVPNActive: Bool) async -> Bool {
        let currentWorks = await clients[original.id]?.isReachable() ?? false
        let currentRank = PlexConnectionResolver.rank(of: original.baseURL, settings: original.connection)
        if currentWorks, currentRank <= PlexConnectionResolver.bestPossibleRank(for: original.connection) { return true }
        guard original.kind == .plex, let url = await relocatePlexServer(original, isVPNActive: isVPNActive) else { return currentWorks }
        // A working address is only replaced by a better one.
        let isBetter = PlexConnectionResolver.rank(of: url, settings: original.connection) < currentRank
        if currentWorks, !isBetter || url == original.baseURL { return true }
        guard let account = accounts.first(where: { $0.id == original.id }), (try? move(account, to: url)) != nil else { return currentWorks }
        return await clients[account.id]?.isReachable() ?? false
    }

    private func relocatePlexServer(_ account: ServerAccount, isVPNActive: Bool) async -> URL? {
        guard account.kind == .plex, let accountToken = tokens[Self.plexAccountKey], let configuration else { return nil }
        guard let candidate = try? await PlexAccountService(identity: configuration.plexIdentity)
            .servers(accountToken: accountToken)
            .first(where: { $0.id == account.id })
        else { return nil }
        return try? await PlexConnectionResolver(identity: configuration.plexIdentity)
            .resolveConnection(candidate, settings: account.connection, isVPNActive: isVPNActive)
            .url
    }

    private func move(_ account: ServerAccount, to url: URL) throws {
        var updated = account
        updated.baseURL = url
        try reconnect(updated)
    }

    /// Saves `account` and makes a new client for its settings.
    private func reconnect(_ account: ServerAccount) throws {
        guard let token = tokens[account.id] else { throw CoreError.unknownServer }
        try connect(account, token: token)
    }

    private func setOffline(_ isOffline: Bool, serverID: String) {
        if isOffline { offlineServerIDs.insert(serverID) } else { offlineServerIDs.remove(serverID) }
    }

    /// The IP inside a plex.direct name, otherwise the host.
    private static func shortAddress(_ url: URL) -> String {
        guard let host = url.host() else { return url.absoluteString }
        if host.hasSuffix(PlexDirect.suffix), let first = host.split(separator: ".").first {
            return first.replacingOccurrences(of: "-", with: ".")
        }
        return host
    }
}
