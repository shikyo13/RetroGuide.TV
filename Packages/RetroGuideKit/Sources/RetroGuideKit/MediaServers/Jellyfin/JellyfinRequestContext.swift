import Foundation

/// Authenticated request plumbing shared by the Jellyfin server client and loader.
struct JellyfinRequestContext: Sendable {
    let serverID: String
    let baseURL: URL
    let token: String
    let identity: JellyfinClientIdentity
    let http: HTTPClient
    /// Requests a viewer waits on (see ``HTTPClient/playback``).
    let playbackHTTP: HTTPClient

    var builder: RequestBuilder {
        builder(timeout: JellyfinAPI.Defaults.requestTimeout)
    }

    func builder(timeout: TimeInterval) -> RequestBuilder {
        RequestBuilder(baseURL: baseURL, headers: identity.headers(token: token), timeout: timeout)
    }

    /// The token as a query item, for URLs opened by the player or image loader.
    var apiKey: URLQueryItem {
        URLQueryItem(name: JellyfinAPI.Query.apiKey, value: token)
    }

    func itemsPage(query: [URLQueryItem], start: Int, size: Int) async throws -> JellyfinQueryResult<JellyfinItem> {
        let request = try builder.request(path: JellyfinAPI.Path.items, query: query + [
            URLQueryItem(name: "StartIndex", value: String(start)),
            URLQueryItem(name: "Limit", value: String(size)),
            URLQueryItem(name: "EnableTotalRecordCount", value: "true"),
            URLQueryItem(name: "EnableUserData", value: "false"),
        ])
        return try await http.decode(JellyfinQueryResult<JellyfinItem>.self, for: request)
    }

    /// Fetches every page of an item query. Pages are sorted by creation date
    /// and name so they don't overlap, and items repeated across pages anyway
    /// (a library changing mid-download) are kept once.
    func allItems(query: [URLQueryItem]) async throws -> [JellyfinItem] {
        let sorted = query + [URLQueryItem(name: "SortBy", value: "DateCreated,SortName")]
        let pageSize = JellyfinAPI.Defaults.pageSize
        let first = try await itemsPage(query: sorted, start: .zero, size: pageSize)
        var results = first.items ?? []
        let total = first.totalRecordCount ?? results.count
        if total > results.count {
            let offsets = Array(stride(from: pageSize, to: total, by: pageSize))
            let pages = try await offsets.concurrentMap(limit: JellyfinAPI.Defaults.maxConcurrentRequests) { offset in
                try await itemsPage(query: sorted, start: offset, size: pageSize).items ?? []
            }
            results.append(contentsOf: pages.joined())
        }
        var seen = Set<String>()
        return results.filter { seen.insert($0.id).inserted }
    }
}

extension HTTPClient {
    /// This client's session, decoding Jellyfin's PascalCase JSON.
    var jellyfin: HTTPClient {
        decoding(with: JellyfinCoding.decoder)
    }
}
