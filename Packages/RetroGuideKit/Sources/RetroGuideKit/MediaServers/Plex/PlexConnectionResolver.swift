import Foundation

public enum PlexConnectionError: Error, LocalizedError {
    case unreachable(serverName: String)

    public var errorDescription: String? {
        switch self {
        case let .unreachable(name): "Couldn't reach \(name). Make sure the server is running and on the same network."
        }
    }
}

/// Probes every advertised address of a server in parallel and picks the best
/// reachable one (local beats remote beats relay).
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
        let reachable = await withTaskGroup(of: PlexConnectionCandidate?.self) { group in
            for connection in server.connections {
                group.addTask { await isReachable(connection, token: server.accessToken) ? connection : nil }
            }
            var results: [PlexConnectionCandidate] = []
            for await result in group {
                if let result { results.append(result) }
            }
            return results
        }
        guard let best = reachable.min(by: { $0.preferenceRank < $1.preferenceRank }) else {
            throw PlexConnectionError.unreachable(serverName: server.name)
        }
        return (best.url, best.isLocal)
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
