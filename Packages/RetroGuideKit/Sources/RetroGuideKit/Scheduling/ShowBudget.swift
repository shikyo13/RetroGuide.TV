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

    struct Channel: Sendable {
        let context: ScheduleContext
        let ordering: ScheduleOrdering
        let counts: Bool
    }

    /// For each channel, in how many of every ``Tuning/cycles`` cycles each of
    /// its shows takes its turns (nil: a rotating channel, never thinned),
    /// counting only content that has joined the schedule by `time`.
    static func keeps(_ channels: [Channel], limit: Int, asOf time: Int = .max) -> [[Int]?] {
        let views = channels.map { View(channel: $0, asOf: time) }
        let adjustable = views.map { $0.isAdjustable }
        var keeps = channels.map { Array(repeating: Tuning.cycles, count: $0.context.shows.count) }
        // Every channel airing each show, and whether it's a single item there.
        var airedOn: [String: [(channel: Int, show: Int)]] = [:]
        var isSingle: [String: Bool] = [:]
        for (index, view) in views.enumerated() {
            for show in view.present {
                let id = view.context.showIDs[show]
                airedOn[id, default: []].append((index, show))
                isSingle[id] = (isSingle[id] ?? true) && view.counts[show] == 1
            }
        }
        let shows = airedOn.keys.sorted()
        for _ in 0..<Tuning.rounds {
            let shares = views.indices.map { share(views[$0].weights, keeps[$0]) }
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
                keeps[channel] = normalized(keeps[channel], present: views[channel].present)
            }
            guard changed else { break }
        }
        return channels.indices.map { adjustable[$0] ? keeps[$0] : nil }
    }

    /// A channel as of one moment: which shows have joined, with how many
    /// episodes, and how much of its time each takes at full turns (turns
    /// per cycle times its average slot, or for rotating channels its run).
    private struct View {
        let context: ScheduleContext
        let counts: [Int]
        let weights: [Double]
        let present: [Int]
        let isAdjustable: Bool

        init(channel: Channel, asOf time: Int) {
            let context = channel.context
            self.context = context
            var counts = Array(repeating: 0, count: context.shows.count)
            var passes = Array(repeating: 0.0, count: context.shows.count)
            var content = TimeInterval.zero
            for (show, items) in context.shows.enumerated() {
                for item in items where context.effective[item] <= time {
                    counts[show] += 1
                    passes[show] += Double(context.slotLengths[item])
                    content += context.items[item].duration
                }
            }
            self.counts = counts
            present = context.shows.indices.filter { counts[$0] > 0 }
            let rotates = NominalOrders.rotates(ordering: channel.ordering, titles: present.count, content: content)
            isAdjustable = channel.counts && present.count > 1 && !rotates
            if rotates {
                weights = passes
            } else {
                let rounds = CycleSegment.Tuning.shuffledRounds
                weights = context.shows.indices.map { show in
                    guard counts[show] > 0 else { return .zero }
                    let turns: Int
                    switch channel.ordering {
                    case .syndication: turns = 1
                    case .shuffle: turns = rounds
                    case .blockShuffle: turns = rounds * ScheduleConstants.blockShuffleEpisodesPerBlock
                    case .marathon: turns = counts[show]
                    }
                    return Double(turns) * passes[show] / Double(counts[show])
                }
            }
        }
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
    private static func normalized(_ keep: [Int], present: [Int]) -> [Int] {
        guard let most = present.map({ keep[$0] }).max(), most > 0 else {
            return Array(repeating: Tuning.minimumCycles, count: keep.count)
        }
        return keep.map { $0 == 0 ? 0 : min(Tuning.cycles, max(1, $0 * Tuning.cycles / most)) }
    }
}

/// Each channel's show budgets over time: recalculated at every period
/// start from the content that has joined by then, so a budget change, like
/// a content change, takes effect at a known moment and never rewrites the
/// schedule before it.
struct BudgetSchedule: Sendable {
    /// When the budgets change, ascending.
    let changeTimes: [Int]
    private let budgets: [(time: Int, keep: [Int]?)]

    func keep(at time: Int) -> [Int]? {
        guard let first = budgets.first, time >= first.time else { return nil }
        let index = NominalOrders.lastNotAfter(time, upper: budgets.count - 1) { budgets[$0].time }
        return budgets[index].keep
    }

    /// Schedules for `channels`, recalculated at each of `times` (ascending).
    static func make(_ channels: [ShowBudget.Channel], limit: Int, times: [Int]) -> [BudgetSchedule] {
        var perChannel = Array(repeating: [(time: Int, keep: [Int]?)](), count: channels.count)
        // Each moment's budgets stand alone: work them out side by side.
        let byTime = ParallelMap.map(times.indices) { ShowBudget.keeps(channels, limit: limit, asOf: times[$0]) }
        for (time, keeps) in zip(times, byTime) {
            for channel in channels.indices where perChannel[channel].last.map({ $0.keep != keeps[channel] }) ?? true {
                perChannel[channel].append((time, keeps[channel]))
            }
        }
        return perChannel.map { budgets in
            BudgetSchedule(changeTimes: budgets.map(\.time), budgets: budgets)
        }
    }
}
