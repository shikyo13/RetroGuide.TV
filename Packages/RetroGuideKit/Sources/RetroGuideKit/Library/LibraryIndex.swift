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
    /// Server-specific show ids → the shared show id (see ``CrossServerMerge``).
    let showAliases: [String: String]
    /// Item positions by normalized network and collection name, and by
    /// library id, so a rule naming one finds its items without a full scan.
    let positionsByNetwork: [String: [Int]]
    let positionsByCollection: [String: [Int]]
    let positionsByLibrary: [String: [Int]]

    public init(items: [MediaItem], libraries: [MediaLibrary] = []) {
        self.init(items: items, libraries: libraries, showAliases: [:])
    }

    init(items: [MediaItem], libraries: [MediaLibrary], showAliases: [String: String], classification: TitleClassification = .shared) {
        self.showAliases = showAliases
        let sorted = items.sorted { $0.id < $1.id }
        self.items = sorted
        let showDecades = Self.showDecades(sorted)
        // A show's episodes share its ids: look each show up once.
        var classifications: [String: Set<GenreCategory>] = [:]
        var unclassified = Set<String>()
        self.attributes = sorted.map { item in
            var classified = classifications[item.showID]
            if classified == nil, !unclassified.contains(item.showID) {
                classified = item.titleIDs.flatMap { classification.categories(for: $0, kind: item.kind) }
                if let classified {
                    classifications[item.showID] = classified
                } else {
                    unclassified.insert(item.showID)
                }
            }
            return NormalizedAttributes(item, decade: showDecades[item.showID] ?? item.year.map(Decade.containing(year:)), classified: classified)
        }
        self.positionsByID = Dictionary(
            sorted.enumerated().map { ($1.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        self.facets = LibraryFacets(items: sorted, attributes: attributes, libraries: libraries)
        var byNetwork: [String: [Int]] = [:]
        var byCollection: [String: [Int]] = [:]
        var byLibrary: [String: [Int]] = [:]
        for (position, item) in sorted.enumerated() {
            attributes[position].networks.forEach { byNetwork[$0, default: []].append(position) }
            attributes[position].collections.forEach { byCollection[$0, default: []].append(position) }
            item.libraryIDs.forEach { byLibrary[$0, default: []].append(position) }
        }
        positionsByNetwork = byNetwork
        positionsByCollection = byCollection
        positionsByLibrary = byLibrary
    }

    /// Merges snapshots in priority order (see ``CrossServerMerge``).
    public init(snapshots: [LibrarySnapshot], quality: [String: VideoQuality] = [:]) {
        let merged = CrossServerMerge(snapshots: snapshots, quality: quality)
        self.init(items: merged.items, libraries: Self.displayLibraries(for: snapshots), showAliases: merged.showAliases)
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

    /// The decade each show belongs to on decade channels: the one most of its
    /// regular episodes aired in (the earlier on a tie), so a show that ran
    /// across decades is on one decade channel. Specials count only for a
    /// show with no dated regular episodes. Movies keep their own year.
    private static func showDecades(_ items: [MediaItem]) -> [String: Int] {
        var regular: [String: [Int: Int]] = [:]
        var specials: [String: [Int: Int]] = [:]
        for item in items {
            guard let series = item.series, let year = item.year else { continue }
            let decade = Decade.containing(year: year)
            if series.isSpecial {
                specials[item.showID, default: [:]][decade, default: 0] += 1
            } else {
                regular[item.showID, default: [:]][decade, default: 0] += 1
            }
        }
        return specials.merging(regular) { _, regular in regular }.compactMapValues { counts in
            counts.max { lhs, rhs in lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key }?.key
        }
    }

    public static let empty = LibraryIndex(items: [])

    public var isEmpty: Bool {
        items.isEmpty
    }

    public func item(withID id: String) -> MediaItem? {
        positionsByID[id].map { items[$0] }
    }

    func attributes(of item: MediaItem) -> NormalizedAttributes? {
        positionsByID[item.id].map { attributes[$0] }
    }
}

/// Pre-normalized lookup keys for one item.
struct NormalizedAttributes: Sendable {
    let genres: Set<String>
    let categories: Set<GenreCategory>
    let categorySource: CategorySource
    let format: TitleFormat
    let networks: Set<String>
    let collections: Set<String>
    let searchableText: String
    let decade: Int?

    /// `classified`: the title's categories from ``TitleClassification``, if it knows the title.
    init(_ item: MediaItem, decade: Int?, classified: Set<GenreCategory>?, taxonomy: GenreTaxonomy = .shared) {
        genres = TextNormalizer.keys(item.genres)
        let tagged = taxonomy.categories(for: item.genres)
        var categories: Set<GenreCategory>
        if let classified {
            // The server's tags, less the loosely applied ones the
            // classification doesn't confirm; either source's word is enough
            // that a title is unscripted. Untagged titles take the classification.
            categories = tagged.isEmpty
                ? classified
                : tagged.subtracting(GenreCategory.looselyTagged.subtracting(classified))
                    .union(classified.intersection(GenreCategory.unscripted))
            categorySource = .classification
        } else {
            categories = tagged
            categorySource = .server
        }
        if AnimeDetector.isAnime(categories: categories, countries: item.countries) {
            categories.formUnion([.anime, .animation])
        }
        self.categories = categories
        format = categories.isDisjoint(with: GenreCategory.unscripted) ? .scripted : .unscripted
        networks = TextNormalizer.keys(item.networks)
        collections = TextNormalizer.keys(item.collections)
        searchableText = TextNormalizer.key([item.series?.title, item.title].compactMap { $0 }.joined(separator: " "))
        self.decade = decade
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
