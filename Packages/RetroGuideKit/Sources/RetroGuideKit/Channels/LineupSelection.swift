import Foundation

/// Chooses which channels make the lineup when there are more candidates than
/// places: catch-all channels first, then each kind gets its first-pass
/// allowance (``ChannelCategory/firstPassAllowance``), then the remaining
/// places go round-robin across kinds. Within a kind, genre and decade
/// channels keep their catalog order, and network, collection and library
/// channels go by how many titles they carry (the recognisable ones: HBO
/// before a network with three shows). 24/7 channels aren't chosen here.
enum LineupSelection {
    typealias Resolved = (definition: ChannelDefinition, items: [MediaItem])

    /// `channels` in lineup order; returns the chosen ones in the same order.
    static func select(_ channels: [Resolved], capacity: Int) -> [Resolved] {
        guard channels.count > capacity else { return channels }
        var pending = Dictionary(grouping: channels.indices) { ChannelCategory(channels[$0].definition) }
        let titles = channels.map { Set($0.items.map(\.showID)) }
        var chosen: [Int] = []

        /// The highest-scoring candidate, the lower id on a tie.
        func best(_ candidates: [Int], by score: (Int) -> Int) -> Int {
            candidates.max { lhs, rhs in
                let left = score(lhs), right = score(rhs)
                return left != right ? left < right : channels[lhs].definition.id > channels[rhs].definition.id
            } ?? candidates[0]
        }

        func take(from category: ChannelCategory) -> Bool {
            guard chosen.count < capacity, let candidates = pending[category], !candidates.isEmpty else { return false }
            let pick: Int
            switch category {
            case .catchAll, .genre, .decade, .allDay, .custom:
                pick = candidates[0]
            case .network, .collection, .library:
                pick = best(candidates) { titles[$0].count }
            }
            pending[category]?.removeAll { $0 == pick }
            chosen.append(pick)
            return true
        }

        while take(from: .catchAll) {}
        for category in ChannelCategory.allCases where category != .catchAll {
            for _ in 0..<category.firstPassAllowance where take(from: category) {}
        }
        var tookAny = true
        while tookAny {
            tookAny = false
            for category in ChannelCategory.allCases where category != .catchAll {
                tookAny = take(from: category) || tookAny
            }
        }
        return chosen.sorted().map { channels[$0] }
    }
}
