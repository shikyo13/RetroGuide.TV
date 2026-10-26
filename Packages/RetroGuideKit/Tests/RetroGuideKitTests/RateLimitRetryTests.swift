import Foundation
import Testing
@testable import RetroGuideKit

@Suite("Rate limit recovery", .serialized)
struct RateLimitRetryTests {
    private func client(statuses: [Int], retryAfter: String = "0") -> HTTPClient {
        RateLimitProtocol.state.reset(statuses, retryAfter: retryAfter)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RateLimitProtocol.self]
        return HTTPClient(session: URLSession(configuration: configuration))
    }

    private var request: URLRequest { URLRequest(url: URL(string: "https://rate-limit.invalid/pin")!) }

    @Test("A rate-limited request recovers without changing its URL")
    func recovers() async throws {
        let data = try await client(statuses: [429, 200]).data(for: request, rateLimitRetries: 3)
        #expect(String(decoding: data, as: UTF8.self) == "ok")
        #expect(RateLimitProtocol.state.requests.count == 2)
        #expect(RateLimitProtocol.state.requests.allSatisfy { $0.url == request.url })
    }

    @Test("Persistent rate limits stop after the configured retries")
    func bounded() async {
        let http = client(statuses: [429])
        await #expect(throws: HTTPError.status(429)) { try await http.data(for: request, rateLimitRetries: 3) }
        #expect(RateLimitProtocol.state.requests.count == 4)
    }

    @Test("Authentication failures are never retried")
    func unauthorized() async {
        let http = client(statuses: [401])
        await #expect(throws: HTTPError.unauthorized) { try await http.data(for: request, rateLimitRetries: 3) }
        #expect(RateLimitProtocol.state.requests.count == 1)
    }

    @Test("Cancelling a rate-limit wait sends no further requests")
    func cancellation() async {
        let http = client(statuses: [429], retryAfter: "60")
        let request = request
        let task = Task { try await http.data(for: request, rateLimitRetries: 3) }
        while RateLimitProtocol.state.requests.isEmpty { await Task.yield() }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled request unexpectedly completed")
        } catch {
            #expect(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }
        #expect(RateLimitProtocol.state.requests.count == 1)
    }

    @Test("Retry-After seconds and dates take precedence over exponential fallback")
    func delay() {
        #expect(RateLimitRetry.delay(header: "12", attempt: 0) == 12)
        #expect(RateLimitRetry.delay(header: nil, attempt: 0) == 5)
        #expect(RateLimitRetry.delay(header: "invalid", attempt: 1) == 10)
        #expect(RateLimitRetry.delay(header: "600", attempt: 0) == nil)
        #expect(RateLimitRetry.delay(header: "Thu, 01 Jan 1970 00:01:00 GMT", attempt: 0, now: Date(timeIntervalSince1970: 0)) == 60)
    }
}

private final class RateLimitProtocol: URLProtocol, @unchecked Sendable {
    static let state = State()
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var statuses: [Int] = []
        private var retryAfter = "0"
        private var recorded: [URLRequest] = []
        var requests: [URLRequest] { lock.withLock { recorded } }
        func reset(_ statuses: [Int], retryAfter: String) {
            lock.withLock { self.statuses = statuses; self.retryAfter = retryAfter; recorded = [] }
        }
        func response(_ request: URLRequest) -> (Int, String) {
            lock.withLock {
                recorded.append(request)
                let status = statuses.count > 1 ? statuses.removeFirst() : statuses[0]
                return (status, retryAfter)
            }
        }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, delay) = Self.state.response(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Retry-After": delay])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("ok".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
