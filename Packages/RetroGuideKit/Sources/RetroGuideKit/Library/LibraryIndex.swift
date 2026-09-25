import Foundation

/// An immutable, query-optimized view over every item from every connected server.
///
/// Normalized attribute sets are computed once here so that matching dozens of
/// channel rules against tens of thousands of items stays cheap.
public struct LibraryIndex: Sendable {
    public let items: [MediaItem]
    public let facets: LibraryFacets
    let attributes: [NormalizedAttributes]
    private let positionsByID: [String: Int]

    public init(items: [MediaItem], libraries: [MediaLibrary] = []) {
        let sorted = items.sorted { $0.id < $1.id }
        let libraryTitles = Dictionary(libraries.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        self.items = sorted
        self.attributes = sorted.map { NormalizedAttributes($0, libraryTitle: libraryTitles[$0.libraryID]) }
        self.positionsByID = Dictionary(
            sorted.enumerated().map { ($1.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        self.facets = LibraryFacets(items: sorted, attributes: attributes, libraries: libraries)
    }

    /// Merges snapshots in priority order. The same title found on several
    /// servers is kept once, from the highest-priority server; when one server
    /// has it more than once (say a 4K and a 1080p library), the copy that best
    /// matches that server's quality setting wins.
    public init(snapshots: [LibrarySnapshot], quality: [String: VideoQuality] = [:]) {
        var chosen: [String: (priority: Int, item: MediaItem)] = [:]
        var items: [MediaItem] = []
        for (priority, snapshot) in snapshots.enumerated() {
            let preference = quality[snapshot.serverID] ?? .original
            for item in snapshot.items {
                guard let externalID = item.externalID else {
                    items.append(item)
                    continue
                }
                if let existing = chosen[externalID] {
                    guard existing.priority == priority,
                          Self.isBetterFit(item, than: existing.item, for: preference)
                    else { continue }
                }
                chosen[externalID] = (priority, item)
            }
        }
        items.append(contentsOf: chosen.values.map(\.item))
        self.init(items: items, libraries: Self.displayLibraries(for: snapshots))
    }

    private static func isBetterFit(_ candidate: MediaItem, than current: MediaItem, for quality: VideoQuality) -> Bool {
        guard let candidateVersion = MediaVersionSelector.best(of: candidate.versions, for: quality),
              let currentVersion = MediaVersionSelector.best(of: current.versions, for: quality)
        else { return false }
        return MediaVersionSelector.best(of: [currentVersion, candidateVersion], for: quality) == candidateVersion
            && candidateVersion != currentVersion
    }

    /// Libraries with names made unique across servers ("Movies · Home").
    private static func displayLibraries(for snapshots: [LibrarySnapshot]) -> [MediaLibrary] {
        let titleCounts = Dictionary(grouping: snapshots.flatMap(\.libraries), by: \.title).mapValues(\.count)
        return snapshots.flatMap { snapshot in
            snapshot.libraries.map { library in
                guard titleCounts[library.title, default: .zero] > 1 else { return library }
                return MediaLibrary(
                    serverID: library.serverID,
                    key: library.key,
                    title: "\(library.title) · \(snapshot.serverName)",
                    kind: library.kind
                )
            }
        }
    }

    public static let empty = LibraryIndex(items: [])

    public var isEmpty: Bool {
        items.isEmpty
    }

    public func item(withID id: String) -> MediaItem? {
        positionsByID[id].map { items[$0] }
    }
}

/// Pre-normalized lookup keys for one item.
struct NormalizedAttributes: Sendable {
    let genres: Set<String>
    let categories: Set<GenreCategory>
    let networks: Set<String>
    let collections: Set<String>
    let searchableText: String
    let decade: Int?

    init(_ item: MediaItem, libraryTitle: String?, taxonomy: GenreTaxonomy = .shared) {
        genres = TextNormalizer.keys(item.genres)
        var categories = taxonomy.categories(for: item.genres)
        if AnimeDetector.isAnime(categories: categories, countries: item.countries, libraryTitle: libraryTitle) {
            categories.formUnion([.anime, .animation])
        }
        self.categories = categories
        networks = TextNormalizer.keys(item.networks)
        collections = TextNormalizer.keys(item.collections)
        searchableText = TextNormalizer.key([item.series?.title, item.title].compactMap { $0 }.joined(separator: " "))
        decade = item.year.map(Decade.containing(year:))
    }
}

/// Decade helpers ("1987" → 1980).
public enum Decade {
    public static let span = 10

    public static func containing(year: Int) -> Int {
        (year / span) * span
    }

    public static func label(for decade: Int) -> String {
        "\(decade)s"
    }
}
