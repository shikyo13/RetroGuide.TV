import Foundation

/// Why a show or movie is on a channel, for "Why is this here?": which of the
/// channel's criteria it meets, and where its genres came from.
public struct TitlePlacement: Sendable, Hashable {
    /// The title's genre categories, as channels see them.
    public let categories: Set<GenreCategory>
    /// Whether those came from RetroGuide's title classification or the server's tags.
    public let source: CategorySource
    public let format: TitleFormat
    /// The channel's categories the title has (empty when the channel isn't genre-based).
    public let matchedCategories: Set<GenreCategory>
    /// The channel's networks, collections and decades the title belongs to.
    public let matchedNetworks: [String]
    public let matchedCollections: [String]
    public let matchedDecade: Int?
}

extension LibraryIndex {
    /// Why `item` meets `rule`; `nil` when the index doesn't hold the item.
    public func placement(of item: MediaItem, under rule: ChannelRule) -> TitlePlacement? {
        guard let attributes = attributes(of: item) else { return nil }
        return TitlePlacement(
            categories: attributes.categories,
            source: attributes.categorySource,
            format: attributes.format,
            matchedCategories: rule.categories.intersection(attributes.categories),
            matchedNetworks: rule.networks.filter { attributes.networks.contains(TextNormalizer.key($0)) }.sorted(),
            matchedCollections: rule.collections.filter { attributes.collections.contains(TextNormalizer.key($0)) }.sorted(),
            matchedDecade: attributes.decade.flatMap { rule.decades.contains($0) ? $0 : nil }
        )
    }
}
