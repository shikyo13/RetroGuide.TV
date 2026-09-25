import Foundation

/// Authenticated request plumbing shared by the Plex server client and loader.
struct PlexRequestContext: Sendable {
    let serverID: String
    let baseURL: URL
    let token: String
    let identity: PlexClientIdentity
    let http: HTTPClient

    var builder: RequestBuilder {
        RequestBuilder(
            baseURL: baseURL,
            headers: identity.headers.merging([PlexAPI.Header.token: token]) { _, new in new },
            timeout: PlexAPI.Defaults.requestTimeout
        )
    }

    func metadataPage(path: String, query: [URLQueryItem], start: Int, size: Int) async throws -> PlexMetadataPage {
        let request = try builder.request(
            path: path,
            query: query,
            extraHeaders: [
                PlexAPI.Header.containerStart: String(start),
                PlexAPI.Header.containerSize: String(size),
            ]
        )
        return try await http.decode(PlexEnvelope<PlexMetadataPage>.self, for: request).mediaContainer
    }

    /// Fetches every page of a metadata listing.
    func allMetadata(path: String, query: [URLQueryItem] = []) async throws -> [PlexMetadata] {
        let pageSize = PlexAPI.Defaults.pageSize
        let first = try await metadataPage(path: path, query: query, start: .zero, size: pageSize)
        var results = first.metadata ?? []
        let total = first.totalSize ?? results.count
        guard total > results.count else { return results }
        let offsets = Array(stride(from: pageSize, to: total, by: pageSize))
        let pages = try await offsets.concurrentMap(limit: PlexAPI.Defaults.maxConcurrentRequests) { offset in
            try await metadataPage(path: path, query: query, start: offset, size: pageSize).metadata ?? []
        }
        results.append(contentsOf: pages.joined())
        return results
    }

    func directories(path: String) async throws -> [PlexDirectory] {
        let request = try builder.request(path: path)
        return try await http.decode(PlexEnvelope<PlexDirectoryPage>.self, for: request).mediaContainer.directory ?? []
    }
}
