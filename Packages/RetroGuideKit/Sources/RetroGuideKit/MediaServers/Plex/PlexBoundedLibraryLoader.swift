import Foundation

extension PlexLibraryLoader {
    /// Auxiliary catalogs retain metadata only for their selected items and shows.
    /// Membership pages are still scanned completely so restrictions remain accurate.
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
            let type: PlexAPI.MetadataType = library.kind == .movies ? .movie : .episode
            let items = try await context.allMetadata(
                path: PlexAPI.Path.sectionItems(library.key),
                query: [URLQueryItem(name: "type", value: String(type.rawValue))] + PlexAPI.Trim.listingWithIDs,
                limit: remaining
            )
            let keys = Set(items.map(\.ratingKey))
            let parents = Set(items.compactMap(\.grandparentRatingKey))
            var shows: [String: PlexMetadata] = [:]
            if !parents.isEmpty {
                try await context.metadataPages(
                    path: PlexAPI.Path.sectionItems(library.key),
                    query: [URLQueryItem(name: "type", value: String(PlexAPI.MetadataType.show.rawValue))] + PlexAPI.Trim.listingWithIDs
                ) { page in
                    for show in page where parents.contains(show.ratingKey) { shows[show.ratingKey] = show }
                }
            }
            let tagKeys = library.kind == .movies ? keys : parents
            let tagType: PlexAPI.MetadataType = library.kind == .movies ? .movie : .show
            var memberships = PlexTagMemberships()
            memberships.genres = try await boundedMembership(library, field: PlexAPI.FilterField.genre, type: tagType, keys: tagKeys)
            if library.kind == .shows {
                memberships.networks = try await boundedMembership(library, field: PlexAPI.FilterField.network, type: tagType, keys: tagKeys)
            }
            memberships.collections = try await boundedCollections(library, keys: keys.union(parents))
            result += items.compactMap { item in
                if library.kind == .movies { return PlexItemMapper.movie(item, library: library, memberships: memberships) }
                return PlexItemMapper.episode(item, show: item.grandparentRatingKey.flatMap { shows[$0] }, library: library, memberships: memberships)
            }
        }
        progress(LibraryLoadProgress(fraction: 1, message: "Finishing up…"))
        return result
    }

    private func boundedMembership(
        _ library: MediaLibrary, field: String, type: PlexAPI.MetadataType, keys: Set<String>
    ) async throws -> [String: [String]] {
        guard !keys.isEmpty else { return [:] }
        let tags: [PlexDirectory]
        do { tags = try await context.directories(path: PlexAPI.Path.sectionFilter(library.key, field)) }
        catch HTTPError.status { return [:] }
        var result: [String: [String]] = [:]
        for tag in tags {
            let query = [URLQueryItem(name: "type", value: String(type.rawValue)), URLQueryItem(name: field, value: tag.key)] + PlexAPI.Trim.keysOnly
            try await context.metadataPages(path: PlexAPI.Path.sectionItems(library.key), query: query) { page in
                for item in page where keys.contains(item.ratingKey) {
                    if !(result[item.ratingKey]?.contains(tag.title) ?? false) { result[item.ratingKey, default: []].append(tag.title) }
                }
            }
        }
        return result
    }

    private func boundedCollections(_ library: MediaLibrary, keys: Set<String>) async throws -> [String: [String]] {
        guard !keys.isEmpty else { return [:] }
        var result: [String: [String]] = [:]
        try await context.metadataPages(path: PlexAPI.Path.sectionCollections(library.key)) { collections in
            for collection in collections where (collection.childCount ?? .zero) >= LineupOptions.Defaults.collectionMinimumItems {
                try await context.metadataPages(path: PlexAPI.Path.collectionChildren(collection.ratingKey), query: PlexAPI.Trim.keysOnly) { page in
                    for item in page where keys.contains(item.ratingKey) {
                        if !(result[item.ratingKey]?.contains(collection.title) ?? false) { result[item.ratingKey, default: []].append(collection.title) }
                    }
                }
            }
        }
        return result
    }
}
