import Foundation

/// Drops automatic channels that air nearly the same titles as a more
/// meaningful one (a network channel that's really just the Anime channel).
/// Channels keep their own content, so a genre channel never picks up titles
/// outside its genre; everything dropped still airs on the catch-alls.
/// Catch-alls (Everything, All Shows, Movies) are never dropped.
enum DuplicateChannelMerger {
    typealias Resolved = (definition: ChannelDefinition, items: [MediaItem])

    enum Tuning {
        /// Two channels sharing this much of their combined titles are duplicates.
        static let similarity = 0.6
    }

    /// Lower wins when two channels are duplicates.
    private static let sourceRank: [ChannelSource: Int] = [.curated: 0, .decade: 1, .library: 2, .network: 3, .collection: 4]

    /// Removes duplicates from `channels`, keeping the survivors in their original order.
    static func merge(_ channels: [Resolved]) -> [Resolved] {
        var kept: [(position: Int, titles: Set<String>)] = []
        let ranked = channels.indices.sorted { isMoreMeaningful(channels[$0], than: channels[$1]) }
        for position in ranked {
            let channel = channels[position]
            let own = Set(channel.items.map(title(of:)))
            let isDuplicate = !channel.definition.rule.isCatchAll && kept.contains { other in
                !channels[other.position].definition.rule.isCatchAll
                    && Double(own.intersection(other.titles).count) / Double(own.union(other.titles).count) >= Tuning.similarity
            }
            if !isDuplicate {
                kept.append((position, own))
            }
        }
        return kept.map(\.position).sorted().map { channels[$0] }
    }

    private static func isMoreMeaningful(_ lhs: Resolved, than rhs: Resolved) -> Bool {
        let left = sourceRank[lhs.definition.source] ?? .max
        let right = sourceRank[rhs.definition.source] ?? .max
        return left != right ? left < right : (lhs.definition.number, lhs.definition.id) < (rhs.definition.number, rhs.definition.id)
    }

    static func title(of item: MediaItem) -> String {
        item.showID
    }
}
