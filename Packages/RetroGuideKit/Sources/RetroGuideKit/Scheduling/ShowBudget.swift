import Foundation

/// How often each show comes up on each channel, so that no show is wanted
/// on more channels at once than time allows.
///
/// A movie in several small movie pools, or a show on more channels than the
/// simulcast limit, would otherwise be due in two places at once again and
/// again, and a channel can only step around a clash for so long. Where the
/// channels together would want a show for more time than it can have, the
/// cycling channels that also have other things to air take its turns in
/// fewer cycles, in proportion; rotating channels, single-show channels and
/// custom channels keep theirs. Nothing is removed from any lineup unless the
/// show could never air on that channel anyway.
enum ShowBudget {
    enum Tuning {
        /// Turn budgets are counted in cycles out of this many.
        static let cycles = 16
        /// Share of the time one movie (or any single item) may be wanted
        /// across all channels: it can only be on one at a time.
        static let itemShare = 0.5
        /// Share of the simulcast limit a show may be wanted on, on average.
        static let limitShare = 0.75
        /// Rounds of rebalancing (a channel giving up one show airs its others more).
        static let rounds = 4
        /// The fewest cycles a show is thinned to, so every channel keeps its
        /// mix; only a show that can't fit at all is dropped from a channel.
        static let minimumCycles = cycles / 4
    }

    struct Channel {
        let context: ScheduleContext
        let ordering: ScheduleOrdering
        let counts: Bool
    }

    /// For each channel, in how many of every ``Tuning/cycles`` cycles each of
    /// its shows takes its turns (nil: a rotating channel, never thinned).
    static func keeps(_ channels: [Channel], limit: Int) -> [[Int]?] {
        let weights = channels.map(weights)
        let adjustable = channels.indices.map { channel in
            channels[channel].counts
                && channels[channel].context.shows.count > 1
                && !NominalOrders.rotates(ordering: channels[channel].ordering, items: channels[channel].context.items)
        }
        var keeps = channels.map { Array(repeating: Tuning.cycles, count: $0.context.shows.count) }
        // Every channel airing each show, and whether it's a single item there.
        var airedOn: [String: [(channel: Int, show: Int)]] = [:]
        var isSingle: [String: Bool] = [:]
        for (index, channel) in channels.enumerated() {
            for (show, id) in channel.context.showIDs.enumerated() {
                airedOn[id, default: []].append((index, show))
                isSingle[id] = (isSingle[id] ?? true) && channel.context.shows[show].count == 1
            }
        }
        let shows = airedOn.keys.sorted()
        for _ in 0..<Tuning.rounds {
            let shares = channels.indices.map { share(weights[$0], keeps[$0]) }
            var changed = false
            for id in shows {
                let single = isSingle[id] ?? false
                guard single || limit < .max else { continue }
                let capacity = single ? Tuning.itemShare : Double(limit) * Tuning.limitShare
                var fixed = 0.0
                var flexible = 0.0
                for (channel, show) in airedOn[id] ?? [] where single || channels[channel].counts {
                    if adjustable[channel] {
                        flexible += shares[channel][show]
                    } else {
                        fixed += shares[channel][show]
                    }
                }
                guard fixed + flexible > capacity, flexible > .zero else { continue }
                // Channels that can't take fewer turns already fill it: elsewhere it can't air.
                let fits = fixed < capacity
                let scale = fits ? (capacity - fixed) / flexible : 0
                for (channel, show) in airedOn[id] ?? [] where adjustable[channel] {
                    let floor = fits ? min(Tuning.minimumCycles, keeps[channel][show]) : 0
                    let scaled = max(floor, Int((Double(keeps[channel][show]) * scale).rounded(.down)))
                    if scaled < keeps[channel][show] {
                        keeps[channel][show] = scaled
                        changed = true
                    }
                }
            }
            for channel in channels.indices where adjustable[channel] {
                keeps[channel] = normalized(keeps[channel])
            }
            guard changed else { break }
        }
        return channels.indices.map { adjustable[$0] ? keeps[$0] : nil }
    }

    /// How much of a channel's time each show takes at full turns: turns per
    /// cycle times its average slot, or for rotating channels its whole run.
    private static func weights(_ channel: Channel) -> [Double] {
        let context = channel.context
        let passes = context.shows.map { show in Double(show.reduce(0) { $0 + context.slotLengths[$1] }) }
        guard !NominalOrders.rotates(ordering: channel.ordering, items: context.items) else { return passes }
        var turns = Array(repeating: 0, count: context.shows.count)
        for show in CycleOrder.turns(for: channel.ordering, context: context) {
            turns[show] += 1
        }
        return context.shows.indices.map { Double(turns[$0]) * passes[$0] / Double(max(context.shows[$0].count, 1)) }
    }

    /// Each show's share of the channel's time with these budgets.
    private static func share(_ weights: [Double], _ keep: [Int]) -> [Double] {
        let kept = zip(weights, keep).map { $0 * Double($1) }
        let total = kept.reduce(0, +)
        return total > .zero ? kept.map { $0 / total } : kept
    }

    /// Budgets scaled so the channel's most frequent show takes every cycle
    /// (only the proportions matter). A channel that would be left with
    /// nothing keeps everything at the minimum instead.
    private static func normalized(_ keep: [Int]) -> [Int] {
        guard let most = keep.max(), most > 0 else {
            return Array(repeating: Tuning.minimumCycles, count: keep.count)
        }
        return keep.map { $0 == 0 ? 0 : max(1, $0 * Tuning.cycles / most) }
    }
}
