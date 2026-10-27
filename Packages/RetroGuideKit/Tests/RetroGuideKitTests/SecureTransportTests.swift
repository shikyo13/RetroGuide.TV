import Foundation
import Testing
@testable import RetroGuideKit

@Suite("HTTPS server transport")
struct SecureTransportTests {
    @Test func rejectsPlaintextAndEmbeddedCredentials() throws {
        for text in ["http://localhost", "http://192.168.1.2:8096", "http://100.64.0.2", "http://[::1]", "ftp://example.com", "https://user:password@example.com"] {
            let url = try #require(URL(string: text))
            #expect(!SecureTransport.permits(url))
            #expect(throws: HTTPError.secureConnectionRequired) { try RequestBuilder(baseURL: url, headers: ["X-Plex-Token": "test"], timeout: 1).request(path: "/identity") }
        }
        #expect(SecureTransport.permits(URL(string: "https://server.example.com:8920/jellyfin")!))
    }

    @Test func redirectsStayEncryptedAndOnOrigin() {
        let source = URL(string: "https://media.example.com/start")!
        #expect(SecureTransport.permitsRedirect(from: source, to: URL(string: "https://media.example.com:443/end")!))
        for text in ["http://media.example.com/end", "https://other.example.com/end", "https://media.example.com:8920/end", "https://user@media.example.com/end"] {
            #expect(!SecureTransport.permitsRedirect(from: source, to: URL(string: text)!))
        }
    }

    @Test func directRequestsCannotBypassBuilder() async throws {
        let request = URLRequest(url: URL(string: "http://127.0.0.1:1/?api_key=test")!)
        do {
            _ = try await HTTPClient().data(for: request)
            Issue.record("HTTP request was allowed")
        } catch {
            #expect(error as? HTTPError == .secureConnectionRequired)
        }
    }

    @Test func insecureDiscoveryAndTypedAddressesAreRejected() {
        #expect(JellyfinAddress.candidates(from: "http://localhost:8096").isEmpty)
        #expect(JellyfinAddress.candidates(from: "https://user:secret@example.com").isEmpty)
        #expect(PlexCustomAddress.url(from: "http://localhost:32400", serverURL: nil) == nil)
        let insecure = PlexConnectionCandidate(url: URL(string: "http://localhost:32400")!, isLocal: true, isRelay: false)
        let secure = PlexConnectionCandidate(url: URL(string: "https://media.example.com")!, isLocal: false, isRelay: false)
        let server = PlexServerCandidate(id: "test", name: "Test", isOwned: true, accessToken: "test", connections: [insecure, secure])
        #expect(PlexConnectionResolver.probeGroups(server).flatMap { $0 } == [secure])
    }
}
