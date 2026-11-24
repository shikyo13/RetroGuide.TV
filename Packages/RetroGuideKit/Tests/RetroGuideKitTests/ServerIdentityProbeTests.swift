import Foundation
import Testing
@testable import RetroGuideKit

/// A saved address can come to belong to something else: another server, or any
/// web page. The reachability check must notice, and must not hand it the token.
@Suite("Server checks confirm who answers before sending credentials", .serialized)
struct ServerIdentityProbeTests {
    private static let identity = PlexClientIdentity(clientIdentifier: "fixture", product: "RetroGuide.TV", version: "1",
                                                     platform: "Test", platformVersion: "1", device: "Test", deviceName: "Test")

    private func plex(at host: String) -> PlexServerClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IdentityProtocol.self]
        return PlexServerClient(serverID: "server-1", baseURL: URL(string: "https://\(host):32400")!, token: "secret-token",
                                identity: Self.identity, http: HTTPClient(session: URLSession(configuration: configuration)))
    }

    @Test func plexAnswersOnlyForItself() async {
        IdentityProtocol.log.reset()
        #expect(await plex(at: "right.example").isReachable())
        #expect(await !plex(at: "other.example").isReachable())
        #expect(await !plex(at: "html.example").isReachable())
        #expect(IdentityProtocol.log.sawToken == false)
    }
}

private final class IdentityProtocol: URLProtocol, @unchecked Sendable {
    final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var token = false
        var sawToken: Bool { lock.withLock { token } }
        func reset() { lock.withLock { token = false } }
        func record(_ request: URLRequest) {
            let sent = request.value(forHTTPHeaderField: "X-Plex-Token") != nil || (request.url?.query ?? "").contains("secret-token")
            lock.withLock { token = token || sent }
        }
    }
    static let log = Log()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.log.record(request)
        let host = request.url?.host ?? ""
        let (type, body): (String, String) = switch host {
        case "right.example": ("application/json", #"{"MediaContainer":{"machineIdentifier":"server-1"}}"#)
        case "other.example": ("application/json", #"{"MediaContainer":{"machineIdentifier":"server-2"}}"#)
        default: ("text/html", "<html><body>Welcome</body></html>")
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": type])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
