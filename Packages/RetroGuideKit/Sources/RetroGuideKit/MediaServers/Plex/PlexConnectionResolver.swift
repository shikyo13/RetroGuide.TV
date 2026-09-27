import Foundation

public enum PlexConnectionError: Error, LocalizedError {
    case unreachable(serverName: String)

    public var errorDescription: String? {
        switch self {
        case let .unreachable(name):
            "Couldn't reach \(name). If it's your server, make sure it's running. If someone shared it with you, they may need to turn on Remote Access in Plex's settings."
        }
    }
}

/// Probes a server's addresses and picks the best reachable one (custom, then
/// home or VPN, then remote, then relay). See ``probeGroups(_:settings:isVPNActive:)``
/// for the order addresses are tried in.
public struct PlexConnectionResolver: Sendable {
    private let identity: PlexClientIdentity
    private let session: URLSession

    public init(identity: PlexClientIdentity, session: URLSession = .shared) {
        self.identity = identity
        self.session = session
    }

    public func resolve(_ server: PlexServerCandidate) async throws -> URL {
        try await resolveConnection(server).url
    }

    /// The best reachable address and whether it is on the local network.
    public func resolveConnection(
        _ server: PlexServerCandidate,
        settings: ServerConnectionSettings = .automatic,
        isVPNActive: Bool = false
    ) async throws -> (url: URL, isLocal: Bool) {
        for group in Self.probeGroups(server, settings: settings, isVPNActive: isVPNActive) {
            let reachable = await reachableConnections(group, token: server.accessToken)
            if let best = reachable.min(by: { $0.preferenceRank < $1.preferenceRank }) {
                return (best.url, best.isLocal)
            }
        }
        throw PlexConnectionError.unreachable(serverName: server.name)
    }

    /// Addresses to probe, in rounds; the first round with a reachable address wins.
    ///
    /// - A custom address is always tried on its own first.
    /// - "Prefer home" tries home addresses before any others.
    /// - Automatic probes everything at once (home wins), except when plex.tv
    ///   says the device is away and no VPN is up: then remote goes first so a
    ///   home address that can't answer doesn't hold things up.
    static func probeGroups(
        _ server: PlexServerCandidate,
        settings: ServerConnectionSettings = .automatic,
        isVPNActive: Bool = false
    ) -> [[PlexConnectionCandidate]] {
        let home = server.connections.filter(\.isLocal)
        let remote = server.connections.filter { !$0.isLocal }
        var groups: [[PlexConnectionCandidate]]
        switch settings.preference {
        case .preferHome:
            groups = [home, remote]
        case .automatic, .custom:
            groups = server.isOnSameNetwork == false && !isVPNActive ? [remote, home] : [server.connections]
        }
        if let custom = settings.activeCustomAddress {
            let isNearby = NetworkLocation.isLikelyLocal(custom) || NetworkLocation.isLikelyVPN(custom)
            groups.insert([PlexConnectionCandidate(url: custom, isLocal: isNearby, isRelay: false)], at: .zero)
        }
        return groups.filter { !$0.isEmpty }
    }

    /// How good an address is under `settings`; lower is better. Used to decide
    /// whether a working address should give way to a newly found one.
    public static func rank(of url: URL, settings: ServerConnectionSettings) -> Int {
        if let custom = settings.activeCustomAddress, custom == url { return Rank.custom }
        if NetworkLocation.isLikelyLocal(url) || NetworkLocation.isLikelyVPN(url) { return Rank.nearby }
        return Rank.internet
    }

    /// The best rank an address can have under `settings`.
    public static func bestPossibleRank(for settings: ServerConnectionSettings) -> Int {
        settings.activeCustomAddress == nil ? Rank.nearby : Rank.custom
    }

    private enum Rank {
        static let custom = 0
        static let nearby = 1
        static let internet = 2
    }

    private func reachableConnections(_ connections: [PlexConnectionCandidate], token: String) async -> [PlexConnectionCandidate] {
        await withTaskGroup(of: PlexConnectionCandidate?.self) { group in
            for connection in connections {
                group.addTask { await isReachable(connection, token: token) ? connection : nil }
            }
            var results: [PlexConnectionCandidate] = []
            for await result in group {
                if let result { results.append(result) }
            }
            return results
        }
    }

    private func isReachable(_ connection: PlexConnectionCandidate, token: String) async -> Bool {
        let builder = RequestBuilder(
            baseURL: connection.url,
            headers: identity.headers.merging([PlexAPI.Header.token: token]) { _, new in new },
            timeout: PlexAPI.Defaults.probeTimeout
        )
        guard let request = try? builder.request(path: PlexAPI.Path.identity) else { return false }
        do {
            _ = try await HTTPClient(session: session).data(for: request)
            return true
        } catch {
            return false
        }
    }
}
