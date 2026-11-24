import Foundation

/// Asks the server at an address who it is, without credentials.
///
/// Plex answers `/identity` with its machine identifier to anyone, so an address
/// can be checked before the server's token is ever sent to it: a different
/// server, or any web page that happens to answer there, is never mistaken for
/// this one and never receives the token.
struct PlexIdentityProbe: Sendable {
    let identity: PlexClientIdentity
    let http: HTTPClient

    func isServer(_ serverID: String, at baseURL: URL) async -> Bool {
        let builder = RequestBuilder(baseURL: baseURL, headers: identity.headers, timeout: PlexAPI.Defaults.probeTimeout)
        guard let request = try? builder.request(path: PlexAPI.Path.identity),
              let answer = try? await http.decode(PlexEnvelope<PlexServerIdentity>.self, for: request)
        else { return false }
        return answer.mediaContainer.machineIdentifier == serverID
    }
}

struct PlexServerIdentity: Decodable {
    let machineIdentifier: String?
}
