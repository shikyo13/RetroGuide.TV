import Foundation

/// A code the user enters at plex.tv/link to authorize this device.
public struct PlexLinkCode: Sendable, Hashable {
    public let id: Int
    public let code: String
    /// The page where the user types `code` (also encoded as the QR code).
    public let linkURL: URL
}

/// A Plex Media Server the signed-in account can access.
public struct PlexServerCandidate: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let isOwned: Bool
    public let accessToken: String
    let connections: [PlexConnectionCandidate]
}

struct PlexConnectionCandidate: Sendable, Hashable {
    let url: URL
    let isLocal: Bool
    let isRelay: Bool

    /// Lower is better: local first, then direct remote, then Plex relay.
    var preferenceRank: Int {
        if isLocal { return 0 }
        return isRelay ? 2 : 1
    }
}

/// Talks to plex.tv: device linking and server discovery.
public struct PlexAccountService: Sendable {
    private let identity: PlexClientIdentity
    private let http: HTTPClient
    private let builder: RequestBuilder

    public init(identity: PlexClientIdentity, http: HTTPClient = HTTPClient()) {
        self.identity = identity
        self.http = http
        self.builder = RequestBuilder(
            baseURL: PlexAPI.accountBaseURL,
            headers: identity.headers,
            timeout: PlexAPI.Defaults.requestTimeout
        )
    }

    /// Requests a new four-character link code for `plex.tv/link`.
    public func createLinkCode() async throws -> PlexLinkCode {
        let request = try builder.request(
            path: PlexAPI.Path.pins,
            method: "POST",
            query: [URLQueryItem(name: "strong", value: "false")]
        )
        let pin = try await http.decode(PlexPin.self, for: request)
        return PlexLinkCode(id: pin.id, code: pin.code, linkURL: PlexAPI.linkPageURL)
    }

    /// Returns the account token once the user has entered the code, otherwise `nil`.
    public func token(for code: PlexLinkCode) async throws -> String? {
        let request = try builder.request(path: "\(PlexAPI.Path.pins)/\(code.id)")
        let pin = try await http.decode(PlexPin.self, for: request)
        guard let token = pin.authToken, !token.isEmpty else { return nil }
        return token
    }

    /// Lists servers the account can reach, owned servers first.
    public func servers(accountToken: String) async throws -> [PlexServerCandidate] {
        let request = try builder.request(
            path: PlexAPI.Path.resources,
            query: [
                URLQueryItem(name: "includeHttps", value: "1"),
                URLQueryItem(name: "includeRelay", value: "1"),
            ],
            extraHeaders: [PlexAPI.Header.token: accountToken]
        )
        let resources = try await http.decode([PlexResource].self, for: request)
        return resources
            .filter { $0.provides.split(separator: ",").contains("server") }
            .compactMap(Self.candidate)
            .sorted { ($0.isOwned ? 0 : 1, $0.name) < ($1.isOwned ? 0 : 1, $1.name) }
    }

    private static func candidate(from resource: PlexResource) -> PlexServerCandidate? {
        guard let token = resource.accessToken else { return nil }
        let connections = (resource.connections ?? []).compactMap { connection in
            URL(string: connection.uri).map {
                PlexConnectionCandidate(url: $0, isLocal: connection.local, isRelay: connection.relay)
            }
        }
        guard !connections.isEmpty else { return nil }
        return PlexServerCandidate(
            id: resource.clientIdentifier,
            name: resource.name,
            isOwned: resource.owned ?? false,
            accessToken: token,
            connections: connections
        )
    }
}
