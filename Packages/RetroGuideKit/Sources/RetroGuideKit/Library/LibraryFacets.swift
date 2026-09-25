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
    public let genres: [FacetValue]
    public let networks: [FacetValue]
    public let collections: [FacetValue]
    public let series: [FacetValue]
    public let decades: [FacetValue]
    public let libraries: [FacetValue]

    init(items: [MediaItem], libraries sourceLibraries: [MediaLibrary]) {
        let libraryTitles = Dictionary(sourceLibraries.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        genres = Self.aggregate(items) { $0.genres.map { ($0, $0) } }
        networks = Self.aggregate(items) { $0.networks.map { ($0, $0) } }
        collections = Self.aggregate(items) { $0.collections.map { ($0, $0) } }
        series = Self.aggregate(items) { item in
            guard let seriesID = item.seriesID, let title = item.series?.title else { return [] }
            return [(seriesID, title)]
        }
        decades = Self.aggregate(items) { item in
            item.year.map { year in
                let decade = Decade.containing(year: year)
                return [(String(decade), Decade.label(for: decade))]
            } ?? []
        }
        self.libraries = Self.aggregate(items) { [($0.libraryID, libraryTitles[$0.libraryID] ?? $0.libraryID)] }
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
                if let seriesID = item.seriesID {
                    series[key, default: []].insert(seriesID)
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
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
