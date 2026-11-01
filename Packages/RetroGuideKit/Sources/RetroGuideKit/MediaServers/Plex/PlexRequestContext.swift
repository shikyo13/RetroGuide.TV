import Foundation

/// Authenticated request plumbing shared by the Plex server client and loader.
struct PlexRequestContext: Sendable {
    let serverID: String
    let baseURL: URL
    let token: String
    let identity: PlexClientIdentity
    let http: HTTPClient
    /// Requests a viewer waits on (see ``HTTPClient/playback``).
    let playbackHTTP: HTTPClient

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
    func allMetadata(path: String, query: [URLQueryItem] = [], limit: Int? = nil) async throws -> [PlexMetadata] {
        guard limit != .zero else { return [] }
        let pageSize = min(PlexAPI.Defaults.pageSize, limit ?? PlexAPI.Defaults.pageSize)
        let first = try await metadataPage(path: path, query: query, start: .zero, size: pageSize)
        var results = Array((first.metadata ?? []).prefix(limit ?? Int.max))
        let total = min(first.totalSize ?? results.count, limit ?? Int.max)
        guard total > results.count else { return results }
        let offsets = Array(stride(from: pageSize, to: total, by: pageSize))
        let pages = try await offsets.concurrentMap(limit: PlexAPI.Defaults.maxConcurrentRequests) { offset in
            try await metadataPage(path: path, query: query, start: offset, size: min(pageSize, total - offset)).metadata ?? []
        }
        results.append(contentsOf: pages.joined())
        return Array(results.prefix(limit ?? Int.max))
    }

    func directories(path: String) async throws -> [PlexDirectory] {
        let request = try builder.request(path: path)
        return try await http.decode(PlexEnvelope<PlexDirectoryPage>.self, for: request).mediaContainer.directory ?? []
    }
}
