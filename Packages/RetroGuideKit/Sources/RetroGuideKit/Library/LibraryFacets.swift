import Foundation

/// One selectable value of a facet (a genre, network, show, …) with how much content it has.
public struct FacetValue: Sendable, Hashable, Identifiable {
    /// Stable key used in channel rules (a series key for shows, otherwise the display name).
    public let id: String
    public let name: String
    public let itemCount: Int
    public let runtime: TimeInterval
    /// Number of distinct shows among the items (zero for movie-only values).
    public let seriesCount: Int
}

/// Aggregated metadata used to generate dynamic channels and to populate the channel editor.
public struct LibraryFacets: Sendable {
    /// Canonical genre categories (ids are ``GenreCategory`` raw values).
    public let categories: [FacetValue]
    public let genres: [FacetValue]
    public let networks: [FacetValue]
    public let collections: [FacetValue]
    public let series: [FacetValue]
    public let decades: [FacetValue]
    public let libraries: [FacetValue]

    init(items: [MediaItem], attributes: [NormalizedAttributes], libraries sourceLibraries: [MediaLibrary]) {
        let categoriesByItem = Dictionary(zip(items.map(\.id), attributes.map(\.categories)), uniquingKeysWith: { first, _ in first })
        categories = Self.aggregate(items) { item in
            (categoriesByItem[item.id] ?? []).map { ($0.rawValue, $0.displayName) }
        }
        let libraryTitles = Dictionary(sourceLibraries.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        genres = Self.aggregate(items) { $0.genres.map { ($0, $0) } }
        networks = Self.aggregate(items) { $0.networks.map { ($0, $0) } }
        collections = Self.aggregate(items) { $0.collections.map { ($0, $0) } }
        series = Self.aggregate(items) { item in
            guard let title = item.series?.title else { return [] }
            return [(item.showID, title)]
        }
        decades = Self.aggregate(items) { item in
            item.year.map { year in
                let decade = Decade.containing(year: year)
                return [(String(decade), Decade.label(for: decade))]
            } ?? []
        }
        self.libraries = Self.aggregate(items) { item in
            item.libraryIDs.map { ($0, libraryTitles[$0] ?? $0) }
        }
    }

    /// Groups items by the keys `extract` returns, preserving the first display name seen.
    private static func aggregate(
        _ items: [MediaItem],
        extract: (MediaItem) -> [(key: String, name: String)]
    ) -> [FacetValue] {
        var names: [String: String] = [:]
        var counts: [String: Int] = [:]
        var runtimes: [String: TimeInterval] = [:]
        var series: [String: Set<String>] = [:]
        for item in items {
            for (key, name) in extract(item) {
                if names[key] == nil { names[key] = name }
                counts[key, default: .zero] += 1
                runtimes[key, default: .zero] += item.duration
                if item.series != nil {
                    series[key, default: []].insert(item.showID)
                }
            }
        }
        return names
            .map { key, name in
                FacetValue(
                    id: key,
                    name: name,
                    itemCount: counts[key] ?? .zero,
                    runtime: runtimes[key] ?? .zero,
                    seriesCount: series[key]?.count ?? .zero
                )
            }
            // Locale-independent, so every device builds the same lineup.
            .sorted { ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id) }
    }
}
