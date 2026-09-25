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
        self.items = sorted
        self.attributes = sorted.map(NormalizedAttributes.init)
        self.positionsByID = Dictionary(
            sorted.enumerated().map { ($1.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        self.facets = LibraryFacets(items: sorted, libraries: libraries)
    }

    public init(snapshots: [LibrarySnapshot]) {
        self.init(items: snapshots.flatMap(\.items), libraries: snapshots.flatMap(\.libraries))
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
    let networks: Set<String>
    let collections: Set<String>
    let searchableText: String
    let decade: Int?

    init(_ item: MediaItem) {
        genres = TextNormalizer.keys(item.genres)
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
