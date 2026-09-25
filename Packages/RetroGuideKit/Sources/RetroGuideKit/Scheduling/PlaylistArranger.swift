import Foundation

/// Produces the airing order for one schedule cycle.
///
/// Every ordering is a permutation of the same items, so every cycle of a
/// channel has the same total length. That property is what lets
/// ``ChannelTimeline`` locate "now" with simple arithmetic.
enum PlaylistArranger {
    static func arrange(
        _ items: [MediaItem],
        ordering: ScheduleOrdering,
        using generator: inout SeededGenerator
    ) -> [Int] {
        switch ordering {
        case .shuffle:
            return Array(items.indices).shuffled(using: &generator)
        case .blockShuffle:
            let groups = groupedBySeries(items).shuffled(using: &generator)
            return interleave(groups, blockSize: ScheduleConstants.blockShuffleEpisodesPerBlock)
        case .syndication:
            return interleave(groupedBySeries(items), blockSize: 1)
        case .marathon:
            return groupedBySeries(items).flatMap { $0 }
        }
    }

    /// Groups item indices by show (movies become single-item groups), with
    /// episodes in broadcast order and groups sorted by title for stability.
    private static func groupedBySeries(_ items: [MediaItem]) -> [[Int]] {
        var groups: [String: [Int]] = [:]
        for index in items.indices {
            groups[items[index].seriesID ?? items[index].id, default: []].append(index)
        }
        return groups.values
            .map { indices in
                indices.sorted { lhs, rhs in
                    let left = items[lhs].series?.broadcastOrder ?? (.zero, .zero)
                    let right = items[rhs].series?.broadcastOrder ?? (.zero, .zero)
                    return left != right ? left < right : items[lhs].id < items[rhs].id
                }
            }
            .sorted { items[$0[0]].headline < items[$1[0]].headline }
    }

    /// Round-robins through groups taking `blockSize` entries at a time.
    private static func interleave(_ groups: [[Int]], blockSize: Int) -> [Int] {
        var cursors = Array(repeating: 0, count: groups.count)
        var result: [Int] = []
        result.reserveCapacity(groups.reduce(0) { $0 + $1.count })
        var remaining = groups.indices.filter { !groups[$0].isEmpty }
        while !remaining.isEmpty {
            for group in remaining {
                let end = min(cursors[group] + blockSize, groups[group].count)
                result.append(contentsOf: groups[group][cursors[group]..<end])
                cursors[group] = end
            }
            remaining.removeAll { cursors[$0] >= groups[$0].count }
        }
        return result
    }
}
