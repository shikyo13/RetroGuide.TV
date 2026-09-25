import Foundation

/// Downloads a complete, tag-accurate index of Plex movie and show libraries.
struct PlexLibraryLoader: Sendable {
    let context: PlexRequestContext

    func load(
        _ libraries: [MediaLibrary],
        progress: @escaping @Sendable (LibraryLoadProgress) -> Void
    ) async throws -> [MediaItem] {
        let schedulable = libraries.filter(\.isSchedulable)
        var items: [MediaItem] = []
        for (position, library) in schedulable.enumerated() {
            let base = Double(position) / Double(schedulable.count)
            let share = 1 / Double(schedulable.count)
            let report: @Sendable (Double, String) -> Void = { fraction, message in
                progress(LibraryLoadProgress(fraction: base + share * fraction, message: message))
            }
            switch library.kind {
            case .movies: items += try await loadMovies(library, report: report)
            case .shows: items += try await loadShows(library, report: report)
            case .unsupported: continue
            }
        }
        progress(LibraryLoadProgress(fraction: 1, message: "Done"))
        return items
    }

    // MARK: - Movies

    private enum MovieStage {
        static let tags = 0.1
        static let movies = 0.5
    }

    private func loadMovies(
        _ library: MediaLibrary,
        report: @Sendable (Double, String) -> Void
    ) async throws -> [MediaItem] {
        report(.zero, "Reading \(library.title)…")
        var memberships = PlexTagMemberships()
        memberships.genres = try await membership(library, field: PlexAPI.FilterField.genre, type: .movie)
        memberships.collections = try await collectionMembership(library)
        report(MovieStage.tags, "Reading \(library.title) movies…")
        let movies = try await context.allMetadata(path: PlexAPI.Path.sectionItems(library.key), query: typeQuery(.movie))
        report(MovieStage.movies, "Indexed \(movies.count) movies")
        return movies.compactMap { PlexItemMapper.movie($0, library: library, memberships: memberships) }
    }

    // MARK: - Shows

    private enum ShowStage {
        static let shows = 0.1
        static let tags = 0.3
    }

    private func loadShows(
        _ library: MediaLibrary,
        report: @Sendable (Double, String) -> Void
    ) async throws -> [MediaItem] {
        report(.zero, "Reading \(library.title)…")
        let path = PlexAPI.Path.sectionItems(library.key)
        let shows = try await context.allMetadata(path: path, query: typeQuery(.show))
        let showsByKey = Dictionary(shows.map { ($0.ratingKey, $0) }, uniquingKeysWith: { first, _ in first })
        report(ShowStage.shows, "Reading genres and networks in \(library.title)…")

        var memberships = PlexTagMemberships()
        memberships.genres = try await membership(library, field: PlexAPI.FilterField.genre, type: .show)
        memberships.networks = try await membership(library, field: PlexAPI.FilterField.network, type: .show)
        memberships.collections = try await collectionMembership(library)
        report(ShowStage.tags, "Reading episodes in \(library.title)…")

        let episodes = try await context.allMetadata(path: path, query: typeQuery(.episode))
        report(1, "Indexed \(episodes.count) episodes from \(shows.count) shows")
        return episodes.compactMap { episode in
            PlexItemMapper.episode(
                episode,
                show: episode.grandparentRatingKey.flatMap { showsByKey[$0] },
                library: library,
                memberships: memberships
            )
        }
    }

    // MARK: - Tag membership

    /// Maps `ratingKey → [tag]` for a filter field by querying each tag's filtered listing.
    private func membership(
        _ library: MediaLibrary,
        field: String,
        type: PlexAPI.MetadataType
    ) async throws -> [String: [String]] {
        let tags: [PlexDirectory]
        do {
            tags = try await context.directories(path: PlexAPI.Path.sectionFilter(library.key, field))
        } catch HTTPError.status {
            return [:] // Older servers don't support every filter field.
        }
        let path = PlexAPI.Path.sectionItems(library.key)
        let pairs = try await tags.concurrentMap(limit: PlexAPI.Defaults.maxConcurrentRequests) { tag in
            let query = typeQuery(type) + [URLQueryItem(name: field, value: tag.key)]
            let members = try await context.allMetadata(path: path, query: query)
            return (tag.title, members.map(\.ratingKey))
        }
        return invert(pairs)
    }

    private func collectionMembership(_ library: MediaLibrary) async throws -> [String: [String]] {
        let collections = try await context.allMetadata(path: PlexAPI.Path.sectionCollections(library.key))
        let pairs = try await collections.concurrentMap(limit: PlexAPI.Defaults.maxConcurrentRequests) { collection in
            let children = try await context.allMetadata(path: PlexAPI.Path.collectionChildren(collection.ratingKey))
            return (collection.title, children.map(\.ratingKey))
        }
        return invert(pairs)
    }

    private func invert(_ pairs: [(String, [String])]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for (tag, keys) in pairs {
            for key in keys {
                result[key, default: []].append(tag)
            }
        }
        return result
    }

    private func typeQuery(_ type: PlexAPI.MetadataType) -> [URLQueryItem] {
        [URLQueryItem(name: "type", value: String(type.rawValue))]
    }
}
