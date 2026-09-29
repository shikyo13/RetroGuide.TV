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
            let groups = groupedBySeries(items).map { $0.shuffled(using: &generator).map { [$0] } }
            return spread(groups, phase: .jittered, using: &generator)
        case .blockShuffle:
            let groups = groupedBySeries(items).map { chunked($0, size: ScheduleConstants.blockShuffleEpisodesPerBlock) }
            return spread(groups, phase: .jittered, using: &generator)
        case .syndication:
            let groups = groupedBySeries(items).map { $0.map { [$0] } }
            return spread(groups, phase: .evenlySpaced, using: &generator)
        case .marathon:
            return groupedBySeries(items).flatMap { $0 }
        }
    }

    private enum Phase {
        /// Each unit lands somewhere random within its share of the cycle.
        case jittered
        /// A show's units are exactly evenly spaced from one random start.
        case evenlySpaced
    }

    /// Lays each group's units (episodes or blocks, in order) out evenly across
    /// the whole cycle: a show with `n` units gets one in each `1/n` of it. Short
    /// shows therefore air throughout the cycle instead of running out early and
    /// leaving the rest to the longest-running shows.
    private static func spread(_ groups: [[[Int]]], phase: Phase, using generator: inout SeededGenerator) -> [Int] {
        var placed: [(position: Double, tieBreak: UInt64, unit: [Int])] = []
        placed.reserveCapacity(groups.reduce(0) { $0 + $1.count })
        for units in groups where !units.isEmpty {
            let share = 1 / Double(units.count)
            let start = Double.random(in: 0..<1, using: &generator)
            for (slot, unit) in units.enumerated() {
                let offset = phase == .jittered ? Double.random(in: 0..<1, using: &generator) : start
                placed.append((position: (Double(slot) + offset) * share, tieBreak: generator.next(), unit: unit))
            }
        }
        return placed
            .sorted { $0.position != $1.position ? $0.position < $1.position : $0.tieBreak < $1.tieBreak }
            .flatMap(\.unit)
    }

    private static func chunked(_ indices: [Int], size: Int) -> [[Int]] {
        stride(from: 0, to: indices.count, by: size).map { Array(indices[$0..<min($0 + size, indices.count)]) }
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
}
