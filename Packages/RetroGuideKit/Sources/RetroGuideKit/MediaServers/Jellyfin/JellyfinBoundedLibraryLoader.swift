import Foundation

extension JellyfinLibraryLoader {
    func loadBounded(
        _ libraries: [MediaLibrary], limit: Int,
        progress: @escaping @Sendable (LibraryLoadProgress) -> Void
    ) async throws -> [MediaItem] {
        guard limit > 0 else { return [] }
        var result: [MediaItem] = []
        for library in libraries where library.isSchedulable {
            let remaining = limit - result.count
            guard remaining > 0 else { break }
            progress(LibraryLoadProgress(fraction: .zero, message: "Reading \(library.title)…"))
            let items = try await context.allItems(query: boundedListing(library, type: library.kind == .movies ? JellyfinAPI.ItemType.movie : JellyfinAPI.ItemType.episode, fields: JellyfinAPI.Fields.playable), limit: remaining)
            let parents = Set(items.compactMap(\.seriesId))
            var shows: [String: JellyfinItem] = [:]
            if !parents.isEmpty {
                try await context.itemPages(query: boundedListing(library, type: JellyfinAPI.ItemType.series, fields: JellyfinAPI.Fields.titles)) { page in
                    for show in page where parents.contains(show.id) { shows[show.id] = show }
                }
            }
            let collections = try await boundedCollections(keys: Set(items.map(\.id)).union(parents))
            let networks = JellyfinNetworks(shows: Array(shows.values))
            result += items.compactMap { item in
                if library.kind == .movies { return JellyfinItemMapper.movie(item, library: library, collections: collections) }
                let show = item.seriesId.flatMap { shows[$0] }
                return JellyfinItemMapper.episode(item, series: show, networks: networks.networks(of: show), library: library, collections: collections)
            }
        }
        progress(LibraryLoadProgress(fraction: 1, message: "Finishing up…"))
        return result
    }

    private func boundedCollections(keys: Set<String>) async throws -> [String: [String]] {
        guard !keys.isEmpty else { return [:] }
        var result: [String: [String]] = [:]
        try await context.itemPages(query: [
            URLQueryItem(name: "IncludeItemTypes", value: JellyfinAPI.ItemType.boxSet),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "ChildCount"),
        ]) { collections in
            for collection in collections where (collection.childCount ?? .zero) >= LineupOptions.Defaults.collectionMinimumItems {
                guard let name = collection.name, !name.isEmpty else { continue }
                try await context.itemPages(query: [
                    URLQueryItem(name: "ParentId", value: collection.id),
                    URLQueryItem(name: "Fields", value: JellyfinAPI.Fields.idsOnly),
                ]) { page in
                    for item in page where keys.contains(item.id) {
                        if !(result[item.id]?.contains(name) ?? false) { result[item.id, default: []].append(name) }
                    }
                }
            }
        }
        return result
    }

    private func boundedListing(_ library: MediaLibrary, type: String, fields: String) -> [URLQueryItem] {
        [
            URLQueryItem(name: "ParentId", value: library.key),
            URLQueryItem(name: "IncludeItemTypes", value: type),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: fields),
            URLQueryItem(name: "LocationTypes", value: "FileSystem"),
        ]
    }
}
