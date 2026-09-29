import Foundation

/// Runs a channel the way a real network runs a lineup.
///
/// A few *slots* are on the air at once. Each turn a slot airs the next
/// episode (or block of episodes) of its show, so shows share airtime evenly
/// and always continue where they left off: a 500-episode show simply takes
/// longer to get through, like Bleach on Toonami. After a stint (about a TV
/// season) or at the end of the show, the slot hands over to the next show in
/// the channel's pool, so every show gets its turn and finished shows rest.
///
/// A show that may not air at the moment (it's on enough other channels)
/// passes its turn and picks up where it left off on the next one.
struct RotationPicker: ProgramPicker {
    struct Plan: Sendable, Hashable {
        /// Shows on the air at once.
        var slots: Int
        /// Episodes a show airs per turn.
        var episodesPerTurn: Int
        /// Episodes before a show rotates out (`nil`: until the show ends).
        var episodesPerStint: Int?
        /// Mix up the order of turns every round.
        var shufflesTurns: Bool

        static let showRotation = Plan(slots: Tuning.slots, episodesPerTurn: 1, episodesPerStint: Tuning.episodesPerStint, shufflesTurns: false)
        static let blockShuffle = Plan(slots: Tuning.slots, episodesPerTurn: ScheduleConstants.blockShuffleEpisodesPerBlock, episodesPerStint: Tuning.episodesPerStint, shufflesTurns: true)
        static let marathon = Plan(slots: 1, episodesPerTurn: .max, episodesPerStint: nil, shufflesTurns: false)
    }

    enum Tuning {
        static let slots = 6
        /// Shows in the pool per show on the air, so a finished show can always rest.
        static let showsPerSlot = 3
        /// About one TV season.
        static let episodesPerStint = 26
        /// Rotation needs depth: enough content and enough shows waiting that a
        /// finished show can always rest. Smaller channels air everything once, in
        /// a fixed order, before anything repeats instead (``CyclePicker``).
        static let minimumContent: TimeInterval = 28 * 24 * ScheduleConstants.secondsPerHour
        static let minimumShows = 6
        /// A show that has aired all its episodes rests this long before coming
        /// back (FAST channels lose viewers when repeats show up within weeks).
        static let restAfterFinishing: TimeInterval = 21 * 24 * ScheduleConstants.secondsPerHour
    }

    private let plan: Plan
    private var offset: TimeInterval = .zero
    /// Next episode of every show.
    private var episode: [Int]
    /// Show on the air in each slot, and episodes it has aired this stint.
    private var slotShow: [Int] = []
    private var slotAired: [Int] = []
    /// Slots each show currently holds.
    private var onAir: [Int]
    /// Slot whose turn it is, episodes aired this turn, and the round number.
    private var turnSlot = 0
    private var turnAired = 0
    private var round = 0
    private var roundOrder: [Int] = []
    /// When each show last aired, and until when a finished show rests.
    private var lastAired: [TimeInterval]
    private var restingUntil: [TimeInterval]
    /// Fixed tie-break between shows that have waited equally long.
    private let rank: [Int]

    init(plan requested: Plan, context: ScheduleContext) {
        let showCount = context.shows.count
        let poolSlots = requested.slots == 1 ? 1 : max(2, showCount / Tuning.showsPerSlot)
        plan = Plan(
            slots: max(1, min(requested.slots, poolSlots, showCount)),
            episodesPerTurn: max(1, requested.episodesPerTurn),
            episodesPerStint: requested.episodesPerStint,
            shufflesTurns: requested.shufflesTurns
        )
        var generator = SeededGenerator(seed: context.seed)
        var rank = Array(repeating: 0, count: showCount)
        for (position, show) in Array(0..<showCount).shuffled(using: &generator).enumerated() {
            rank[show] = position
        }
        self.rank = rank
        let never = -TimeInterval.greatestFiniteMagnitude
        episode = Array(repeating: 0, count: showCount)
        onAir = Array(repeating: 0, count: showCount)
        lastAired = Array(repeating: never, count: showCount)
        restingUntil = Array(repeating: never, count: showCount)
        for _ in 0..<plan.slots {
            let show = nextFromPool(showCount: showCount) ?? 0
            slotShow.append(show)
            slotAired.append(0)
            onAir[show] += 1
        }
        roundOrder = Self.roundOrder(slots: plan.slots, round: 0, shuffled: plan.shufflesTurns, seed: context.seed)
    }

    mutating func next(at offset: TimeInterval, in context: ScheduleContext, isAllowed: (Int) -> Bool) -> Int {
        self.offset = offset
        // A show that may not air now (it's on enough other channels) passes
        // its turn; if every slot's show is blocked, one hands its slot to a
        // show from the pool.
        let firstSlot = turnSlot
        for _ in 0..<roundOrder.count {
            let slot = roundOrder[turnSlot]
            if isAllowed(nextItem(of: slotShow[slot], in: context)) {
                return air(slot: slot, in: context)
            }
            passTurn()
        }
        turnSlot = firstSlot
        let slot = roundOrder[turnSlot]
        if let replacement = nextFromPool(showCount: context.shows.count, allowed: { isAllowed(nextItem(of: $0, in: context)) }) {
            replace(slot: slot, with: replacement)
        }
        // Nothing may air: better a simulcast than dead air.
        return air(slot: slot, in: context)
    }

    private func nextItem(of show: Int, in context: ScheduleContext) -> Int {
        context.shows[show][episode[show]]
    }

    /// Airs the slot's next episode and advances turns, stints and the pool.
    private mutating func air(slot: Int, in context: ScheduleContext) -> Int {
        let show = slotShow[slot]
        let item = context.shows[show][episode[show]]
        episode[show] += 1
        slotAired[slot] += 1
        turnAired += 1

        let finished = episode[show] >= context.shows[show].count
        let stintOver = plan.episodesPerStint.map { slotAired[slot] >= $0 } ?? false
        lastAired[show] = offset
        if finished {
            episode[show] = 0
            restingUntil[show] = offset + Tuning.restAfterFinishing
        }
        if finished || stintOver {
            // A stint that ends with every waiting show still resting just
            // continues: better more of a long show than an early rerun.
            if finished || hasRestedShow(showCount: context.shows.count) {
                onAir[show] -= 1
                let replacement = nextFromPool(showCount: context.shows.count) ?? show
                slotShow[slot] = replacement
                onAir[replacement] += 1
            }
            slotAired[slot] = 0
        }
        if finished || stintOver || turnAired >= plan.episodesPerTurn {
            endTurn(context: context)
        }
        return item
    }

    private mutating func replace(slot: Int, with show: Int) {
        onAir[slotShow[slot]] -= 1
        slotShow[slot] = show
        slotAired[slot] = 0
        onAir[show] += 1
    }

    /// Moves on to the next slot within the round without ending it.
    private mutating func passTurn() {
        turnAired = 0
        turnSlot = (turnSlot + 1) % roundOrder.count
    }

    private mutating func endTurn(context: ScheduleContext) {
        turnAired = 0
        turnSlot += 1
        if turnSlot >= roundOrder.count {
            turnSlot = 0
            round += 1
            roundOrder = Self.roundOrder(slots: plan.slots, round: round, shuffled: plan.shufflesTurns, seed: context.seed)
        }
    }

    private func hasRestedShow(showCount: Int) -> Bool {
        (0..<showCount).contains { onAir[$0] == 0 && restingUntil[$0] <= offset }
    }

    /// The show off the air that has waited longest, skipping finished shows
    /// still resting unless every show is resting (small pools), in which
    /// case the one whose rest ends first comes back.
    private func nextFromPool(showCount: Int) -> Int? {
        var best: Int?
        var soonestRested: Int?
        for show in 0..<showCount where onAir[show] == 0 {
            if restingUntil[show] > offset {
                if soonestRested.map({ restingUntil[show] < restingUntil[$0] }) ?? true {
                    soonestRested = show
                }
            } else if best.map({ waitedLonger(show, than: $0) }) ?? true {
                best = show
            }
        }
        return best ?? soonestRested
    }

    /// The show off the air that may air now: the rested one that has waited
    /// longest, or else the one whose rest ends first (an early rerun beats
    /// a show on too many channels at once).
    private func nextFromPool(showCount: Int, allowed: (Int) -> Bool) -> Int? {
        var best: Int?
        var soonestRested: Int?
        for show in 0..<showCount where onAir[show] == 0 && allowed(show) {
            if restingUntil[show] > offset {
                if soonestRested.map({ restingUntil[show] < restingUntil[$0] }) ?? true {
                    soonestRested = show
                }
            } else if best.map({ waitedLonger(show, than: $0) }) ?? true {
                best = show
            }
        }
        return best ?? soonestRested
    }

    private func waitedLonger(_ show: Int, than other: Int) -> Bool {
        lastAired[show] < lastAired[other] || (lastAired[show] == lastAired[other] && rank[show] < rank[other])
    }

    private static func roundOrder(slots: Int, round: Int, shuffled: Bool, seed: UInt64) -> [Int] {
        guard shuffled else { return Array(0..<slots) }
        var generator = SeededGenerator(seed: seed ^ StableHash.fnv1a("round\(round)"))
        return Array(0..<slots).shuffled(using: &generator)
    }
}
