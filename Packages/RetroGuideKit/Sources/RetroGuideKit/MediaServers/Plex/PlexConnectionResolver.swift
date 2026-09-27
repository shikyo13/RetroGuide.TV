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

/// Probes a server's advertised addresses and picks the best reachable one
/// (local beats remote beats relay). When plex.tv says the device is away from
/// the server's network, remote addresses are tried first so a home address
/// that can't answer doesn't hold things up; home addresses are still tried
/// afterwards for devices that reach home over a VPN.
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
    public func resolveConnection(_ server: PlexServerCandidate) async throws -> (url: URL, isLocal: Bool) {
        for group in Self.probeGroups(server) {
            let reachable = await reachableConnections(group, token: server.accessToken)
            if let best = reachable.min(by: { $0.preferenceRank < $1.preferenceRank }) {
                return (best.url, best.isLocal)
            }
        }
        throw PlexConnectionError.unreachable(serverName: server.name)
    }

    /// Addresses to probe, in rounds: everything at once, or remote before home
    /// when the device is known to be away from the server's network.
    static func probeGroups(_ server: PlexServerCandidate) -> [[PlexConnectionCandidate]] {
        guard server.isOnSameNetwork == false else { return [server.connections] }
        let remote = server.connections.filter { !$0.isLocal }
        let home = server.connections.filter(\.isLocal)
        return [remote, home].filter { !$0.isEmpty }
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
