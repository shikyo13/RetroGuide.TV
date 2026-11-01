import Foundation
import Testing
@testable import RetroGuideKit

@Suite("Bounded auxiliary library loading", .serialized)
struct BoundedLibraryLoadingTests {
    func client(_ provider: ServerKind, total: Int = 100_000) -> any MediaServerClient {
        LibraryPageProtocol.requests.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LibraryPageProtocol.self]
        let http = HTTPClient(session: URLSession(configuration: configuration))
        let url = URL(string: "https://\(provider.rawValue)-\(total).invalid")!
        switch provider {
        case .plex:
            return PlexServerClient(serverID: "server", baseURL: url, token: "fixture", identity: PlexClientIdentity(clientIdentifier: "fixture", product: "RetroGuide.TV", version: "1.7", platform: "Test", platformVersion: "1", device: "Test", deviceName: "Test"), http: http)
        case .jellyfin:
            return JellyfinServerClient(serverID: "server", baseURL: url, token: "fixture", userID: "user", identity: JellyfinClientIdentity(deviceID: "fixture", deviceName: "Test", client: "RetroGuide.TV", version: "1.7"), http: http)
        }
    }
    var libraries: [MediaLibrary] {
        ["ads", "unused"].map { MediaLibrary(serverID: "server", key: $0, title: $0, kind: .movies) }
    }
    @Test("Large libraries stop requesting video metadata at the shared limit", arguments: ServerKind.allCases)
    func limitsPages(_ provider: ServerKind) async throws {
        let client = client(provider)
        let items = try await client.fetchItems(in: libraries, limit: 2_001, progress: { _ in })
        #expect(items.count == 2_001)
        #expect(Set(items.map(\.id)).count == 2_001)
        #expect(items.allSatisfy { $0.libraryID == "server/ads" && $0.duration == 15 && $0.contentRating == "G" })
        let requests = LibraryPageProtocol.requests.values
        #expect(requests.map(\.size).reduce(0, +) == 2_001)
        #expect(requests.allSatisfy { $0.start + $0.size <= 2_001 })
    }
    @Test("Zero and negative limits do not contact the server", arguments: ServerKind.allCases)
    func emptyLimit(_ provider: ServerKind) async throws {
        let client = client(provider)
        for limit in [0, -1] {
            let items = try await client.fetchItems(in: libraries, limit: limit, progress: { _ in })
            #expect(items.isEmpty)
        }
        #expect(LibraryPageProtocol.requests.values.isEmpty)
    }
    @Test("Regular library loading remains complete", arguments: ServerKind.allCases)
    func regularLoading(_ provider: ServerKind) async throws {
        let client = client(provider, total: 2_500)
        let items = try await client.fetchItems(in: [libraries[0]], progress: { _ in })
        #expect(items.count == 2_500)
    }
}

private final class LibraryRequestLog: @unchecked Sendable {
    struct Page { let start: Int; let size: Int }
    private let lock = NSLock()
    private var pages: [Page] = []
    var values: [Page] { lock.withLock { pages } }
    func reset() { lock.withLock { pages = [] } }
    func append(start: Int, size: Int) { lock.withLock { pages.append(Page(start: start, size: size)) } }
}

private final class LibraryPageProtocol: URLProtocol, @unchecked Sendable {
    static let requests = LibraryRequestLog()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let query = Dictionary((URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        let isPlex = url.host!.hasPrefix("plex")
        let isListing = isPlex ? url.path.hasSuffix("/all") : query["IncludeItemTypes"] == "Movie"
        let total = Int(url.host!.split(separator: "-")[1].split(separator: ".")[0])!
        let start = Int(isPlex ? request.value(forHTTPHeaderField: "X-Plex-Container-Start") ?? "0" : query["StartIndex"] ?? "0")!
        let size = Int(isPlex ? request.value(forHTTPHeaderField: "X-Plex-Container-Size") ?? "0" : query["Limit"] ?? "0")!
        var payload: [String: Any]
        if isListing {
            Self.requests.append(start: start, size: size)
            let rows: [[String: Any]] = (start..<min(start + size, total)).map { index in
                isPlex ? ["ratingKey": "\(index)", "title": "Clip \(index)", "duration": 15_000, "contentRating": "G"] :
                    ["Id": "\(index)", "Name": "Clip \(index)", "RunTimeTicks": 150_000_000, "OfficialRating": "G"]
            }
            payload = isPlex ? ["MediaContainer": ["totalSize": total, "Metadata": rows]] : ["TotalRecordCount": total, "Items": rows]
        } else {
            payload = isPlex ? ["MediaContainer": ["totalSize": 0, "Metadata": [], "Directory": []]] : ["TotalRecordCount": 0, "Items": []]
        }
        let data = try! JSONSerialization.data(withJSONObject: payload)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
