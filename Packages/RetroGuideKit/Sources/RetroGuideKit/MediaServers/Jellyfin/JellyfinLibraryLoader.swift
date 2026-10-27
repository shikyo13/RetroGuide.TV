import Foundation

/// Downloads a complete index of Jellyfin movie and show libraries. Unlike
/// Plex, Jellyfin listings carry full genre and studio lists, so only
/// collections need separate requests.
struct JellyfinLibraryLoader: Sendable {
    let context: JellyfinRequestContext

    private enum Stage {
        static let collections = 0.1
        static let shows = 0.3
    }

    func load(
        _ libraries: [MediaLibrary],
        progress: @escaping @Sendable (LibraryLoadProgress) -> Void
    ) async throws -> [MediaItem] {
        let schedulable = libraries.filter(\.isSchedulable)
        guard !schedulable.isEmpty else { return [] }
        progress(LibraryLoadProgress(fraction: .zero, message: "Reading collections…"))
        // Collections span libraries on Jellyfin, so they're read once.
        let collections = try await collectionMembership()
        var items: [MediaItem] = []
        for (position, library) in schedulable.enumerated() {
            let base = Stage.collections + (1 - Stage.collections) * Double(position) / Double(schedulable.count)
            let share = (1 - Stage.collections) / Double(schedulable.count)
            let report: @Sendable (Double, String) -> Void = { fraction, message in
                progress(LibraryLoadProgress(fraction: base + share * fraction, message: message))
            }
            switch library.kind {
            case .movies: items += try await loadMovies(library, collections: collections, report: report)
            case .shows: items += try await loadShows(library, collections: collections, report: report)
            case .unsupported: continue
            }
        }
        progress(LibraryLoadProgress(fraction: 1, message: "Finishing up…"))
        return items
    }

    private func loadMovies(
        _ library: MediaLibrary,
        collections: [String: [String]],
        report: @Sendable (Double, String) -> Void
    ) async throws -> [MediaItem] {
        report(.zero, "Reading \(library.title) movies…")
        let movies = try await context.allItems(query: listing(in: library, type: JellyfinAPI.ItemType.movie, fields: JellyfinAPI.Fields.playable))
        report(1, "Indexed \(movies.count) movies")
        return movies.compactMap { JellyfinItemMapper.movie($0, library: library, collections: collections) }
    }

    private func loadShows(
        _ library: MediaLibrary,
        collections: [String: [String]],
        report: @Sendable (Double, String) -> Void
    ) async throws -> [MediaItem] {
        report(.zero, "Reading \(library.title)…")
        let shows = try await context.allItems(query: listing(in: library, type: JellyfinAPI.ItemType.series, fields: JellyfinAPI.Fields.titles))
        let showsByID = Dictionary(shows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let networks = JellyfinNetworks(shows: shows)
        report(Stage.shows, "Reading episodes in \(library.title)…")
        let episodes = try await context.allItems(query: listing(in: library, type: JellyfinAPI.ItemType.episode, fields: JellyfinAPI.Fields.playable))
        report(1, "Indexed \(episodes.count) episodes from \(shows.count) shows")
        return episodes.compactMap { episode in
            let show = episode.seriesId.flatMap { showsByID[$0] }
            return JellyfinItemMapper.episode(
                episode,
                series: show,
                networks: networks.networks(of: show),
                library: library,
                collections: collections
            )
        }
    }

    /// Maps item id → collection names. Only collections large enough to
    /// become a channel are expanded.
    private func collectionMembership() async throws -> [String: [String]] {
        let collections = try await context.allItems(query: [
            URLQueryItem(name: "IncludeItemTypes", value: JellyfinAPI.ItemType.boxSet),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "ChildCount"),
        ]).filter { ($0.childCount ?? .zero) >= LineupOptions.Defaults.collectionMinimumItems }
        let pairs = try await collections.concurrentMap(limit: JellyfinAPI.Defaults.maxConcurrentRequests) { collection in
            let members = try await context.allItems(query: [
                URLQueryItem(name: "ParentId", value: collection.id),
                URLQueryItem(name: "Fields", value: JellyfinAPI.Fields.idsOnly),
            ])
            return (collection.name ?? "", members.map(\.id))
        }
        var result: [String: [String]] = [:]
        for (name, ids) in pairs where !name.isEmpty {
            for id in ids {
                result[id, default: []].append(name)
            }
        }
        return result
    }

    private func listing(in library: MediaLibrary, type: String, fields: String) -> [URLQueryItem] {
        [
            URLQueryItem(name: "ParentId", value: library.key),
            URLQueryItem(name: "IncludeItemTypes", value: type),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: fields),
            URLQueryItem(name: "LocationTypes", value: "FileSystem"),
        ]
    }
}
