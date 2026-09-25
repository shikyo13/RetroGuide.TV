import Foundation

/// Declarative filter describing which items belong on a channel.
///
/// Semantics: every *non-empty* criterion must match (AND), and within a
/// criterion any value may match (OR). Empty criteria are ignored, so an empty
/// rule matches the whole library.
public struct ChannelRule: Codable, Sendable, Hashable {
    public var kinds: Set<MediaKind>
    public var libraryIDs: Set<String>
    /// Canonical genre categories: work across servers, agents and languages.
    public var categories: Set<GenreCategory>
    public var excludedCategories: Set<GenreCategory>
    /// Raw genre names exactly as the server reports them.
    public var genres: Set<String>
    public var excludedGenres: Set<String>
    public var networks: Set<String>
    public var collections: Set<String>
    public var seriesIDs: Set<String>
    public var keywords: Set<String>
    public var audiences: Set<Audience>
    public var decades: Set<Int>

    public init(
        kinds: Set<MediaKind> = [],
        libraryIDs: Set<String> = [],
        categories: Set<GenreCategory> = [],
        excludedCategories: Set<GenreCategory> = [],
        genres: Set<String> = [],
        excludedGenres: Set<String> = [],
        networks: Set<String> = [],
        collections: Set<String> = [],
        seriesIDs: Set<String> = [],
        keywords: Set<String> = [],
        audiences: Set<Audience> = [],
        decades: Set<Int> = []
    ) {
        self.kinds = kinds
        self.libraryIDs = libraryIDs
        self.categories = categories
        self.excludedCategories = excludedCategories
        self.genres = genres
        self.excludedGenres = excludedGenres
        self.networks = networks
        self.collections = collections
        self.seriesIDs = seriesIDs
        self.keywords = keywords
        self.audiences = audiences
        self.decades = decades
    }

    /// Sparse decoding: any missing key means "no constraint". This keeps the
    /// bundled channel catalog JSON short and forward compatible.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kinds = try container.decodeIfPresent(Set<MediaKind>.self, forKey: .kinds) ?? []
        libraryIDs = try container.decodeIfPresent(Set<String>.self, forKey: .libraryIDs) ?? []
        categories = try container.decodeIfPresent(Set<GenreCategory>.self, forKey: .categories) ?? []
        excludedCategories = try container.decodeIfPresent(Set<GenreCategory>.self, forKey: .excludedCategories) ?? []
        genres = try container.decodeIfPresent(Set<String>.self, forKey: .genres) ?? []
        excludedGenres = try container.decodeIfPresent(Set<String>.self, forKey: .excludedGenres) ?? []
        networks = try container.decodeIfPresent(Set<String>.self, forKey: .networks) ?? []
        collections = try container.decodeIfPresent(Set<String>.self, forKey: .collections) ?? []
        seriesIDs = try container.decodeIfPresent(Set<String>.self, forKey: .seriesIDs) ?? []
        keywords = try container.decodeIfPresent(Set<String>.self, forKey: .keywords) ?? []
        audiences = try container.decodeIfPresent(Set<Audience>.self, forKey: .audiences) ?? []
        decades = try container.decodeIfPresent(Set<Int>.self, forKey: .decades) ?? []
    }

    /// Whether the rule has no constraints at all.
    public var isUnconstrained: Bool {
        self == ChannelRule()
    }
}

// MARK: - Matching

extension ChannelRule {
    /// Returns the ids of every item in `index` that satisfies the rule.
    public func matchingItems(in index: LibraryIndex) -> [MediaItem] {
        let compiled = CompiledRule(self)
        return zip(index.items, index.attributes)
            .filter { compiled.matches($0, $1) }
            .map(\.0)
    }
}

/// A rule with its string criteria pre-normalized for fast repeated matching.
struct CompiledRule {
    private let rule: ChannelRule
    private let genres: Set<String>
    private let excludedGenres: Set<String>
    private let networks: Set<String>
    private let collections: Set<String>
    private let keywords: [String]

    init(_ rule: ChannelRule) {
        self.rule = rule
        genres = TextNormalizer.keys(rule.genres)
        excludedGenres = TextNormalizer.keys(rule.excludedGenres)
        networks = TextNormalizer.keys(rule.networks)
        collections = TextNormalizer.keys(rule.collections)
        keywords = rule.keywords.map(TextNormalizer.key)
    }

    func matches(_ item: MediaItem, _ attributes: NormalizedAttributes) -> Bool {
        guard rule.kinds.isEmpty || rule.kinds.contains(item.kind) else { return false }
        guard rule.libraryIDs.isEmpty || rule.libraryIDs.contains(item.libraryID) else { return false }
        guard rule.audiences.isEmpty || rule.audiences.contains(item.audience) else { return false }
        guard rule.categories.isEmpty || !rule.categories.isDisjoint(with: attributes.categories) else { return false }
        guard rule.excludedCategories.isDisjoint(with: attributes.categories) else { return false }
        guard genres.isEmpty || !genres.isDisjoint(with: attributes.genres) else { return false }
        guard excludedGenres.isDisjoint(with: attributes.genres) else { return false }
        guard networks.isEmpty || !networks.isDisjoint(with: attributes.networks) else { return false }
        guard collections.isEmpty || !collections.isDisjoint(with: attributes.collections) else { return false }
        guard rule.decades.isEmpty || attributes.decade.map(rule.decades.contains) == true else { return false }
        if !rule.seriesIDs.isEmpty {
            guard let seriesID = item.seriesID, rule.seriesIDs.contains(seriesID) else { return false }
        }
        if !keywords.isEmpty {
            guard keywords.contains(where: attributes.searchableText.contains) else { return false }
        }
        return true
    }
}
