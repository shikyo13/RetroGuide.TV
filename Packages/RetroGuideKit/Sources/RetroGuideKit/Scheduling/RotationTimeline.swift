import Foundation

/// Schedules a channel the way a real network runs a lineup.
///
/// A few *slots* are on the air at once. Each turn a slot airs the next
/// episode (or block of episodes) of its show, so shows share airtime evenly
/// and always continue where they left off: a 500-episode show simply takes
/// longer to get through, like Bleach on Toonami. After a stint (about a TV
/// season) or at the end of the show, the slot hands over to the next show in
/// the channel's pool, so every show gets its turn and finished shows rest.
///
/// The schedule is simulated forward from ``ScheduleConstants/epoch``, so every
/// device computes the same guide. Pages of programs are cached with the
/// state needed to continue from them.
public final class RotationTimeline: ChannelSchedule, @unchecked Sendable {
    public struct Plan: Sendable, Hashable {
        /// Shows on the air at once.
        public var slots: Int
        /// Episodes a show airs per turn.
        public var episodesPerTurn: Int
        /// Episodes before a show rotates out (`nil`: until the show ends).
        public var episodesPerStint: Int?
        /// Mix up the order of turns every round.
        public var shufflesTurns: Bool

        public static let showRotation = Plan(slots: Tuning.slots, episodesPerTurn: 1, episodesPerStint: Tuning.episodesPerStint, shufflesTurns: false)
        public static let blockShuffle = Plan(slots: Tuning.slots, episodesPerTurn: ScheduleConstants.blockShuffleEpisodesPerBlock, episodesPerStint: Tuning.episodesPerStint, shufflesTurns: true)
        public static let marathon = Plan(slots: 1, episodesPerTurn: .max, episodesPerStint: nil, shufflesTurns: false)
    }

    public enum Tuning {
        public static let slots = 6
        /// Shows in the pool per show on the air, so a finished show can always rest.
        public static let showsPerSlot = 3
        /// About one TV season.
        public static let episodesPerStint = 26
        /// Rotation needs depth: enough content and enough shows waiting that a
        /// finished show can always rest. Smaller channels air everything once, in
        /// a fixed order, before anything repeats instead.
        public static let minimumContent: TimeInterval = 28 * 24 * ScheduleConstants.secondsPerHour
        public static let minimumShows = 6
        /// A show that has aired all its episodes rests this long before coming
        /// back (FAST channels lose viewers when repeats show up within weeks).
        public static let restAfterFinishing: TimeInterval = 21 * 24 * ScheduleConstants.secondsPerHour
        static let programsPerPage = 256
        static let cachedPages = 4
        static let cachedCheckpoints = 8
    }

    public let channelID: String
    private let items: [MediaItem]
    private let slotLengths: [TimeInterval]
    /// Each show's (or movie's) item indices in broadcast order.
    private let shows: [[Int]]
    private let plan: Plan
    private let seed: UInt64

    private let lock = NSLock()
    /// Start offset (from the epoch) of every simulated page.
    private var pageStarts: [TimeInterval] = []
    private var checkpoints: [Int: State] = [:]
    private var pages: [Int: Page] = [:]
    private var pageRecency: [Int] = []

    init(channelID: String, items: [MediaItem], plan: Plan, grid: ScheduleGrid) {
        self.channelID = channelID
        self.items = items
        self.slotLengths = items.map { grid.slotLength(for: $0.duration) }
        self.shows = RotationTimeline.groupedByShow(items)
        let poolSlots = plan.slots == 1 ? 1 : max(2, shows.count / Tuning.showsPerSlot)
        self.plan = Plan(slots: max(1, min(plan.slots, poolSlots, shows.count)), episodesPerTurn: max(1, plan.episodesPerTurn), episodesPerStint: plan.episodesPerStint, shufflesTurns: plan.shufflesTurns)
        self.seed = StableHash.fnv1a(channelID)
    }

    public var isEmpty: Bool {
        !slotLengths.contains { $0 > .zero }
    }

    public func program(at date: Date) -> ScheduledProgram? {
        guard !isEmpty else { return nil }
        let offset = date.timeIntervalSince(ScheduleConstants.epoch)
        guard offset >= .zero else { return nil }
        lock.lock()
        defer { lock.unlock() }
        let pageNumber = page(containing: offset)
        let page = page(pageNumber)
        return makeProgram(page: pageNumber, slot: page.slot(containing: offset), in: page)
    }

    public func program(after program: ScheduledProgram) -> ScheduledProgram? {
        guard !isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        let current = page(program.cycle)
        if program.slot + 1 < current.order.count {
            return makeProgram(page: program.cycle, slot: program.slot + 1, in: current)
        }
        return makeProgram(page: program.cycle + 1, slot: .zero, in: page(program.cycle + 1))
    }

    private func makeProgram(page number: Int, slot: Int, in page: Page) -> ScheduledProgram {
        let item = items[page.order[slot]]
        let start = ScheduleConstants.epoch.addingTimeInterval(page.starts[slot])
        return ScheduledProgram(
            channelID: channelID,
            item: item,
            start: start,
            contentEnd: start.addingTimeInterval(item.duration),
            slotEnd: start.addingTimeInterval(slotLengths[page.order[slot]]),
            cycle: number,
            slot: slot
        )
    }

    // MARK: - Pages

    private struct Page {
        let order: [Int]
        let starts: [TimeInterval]

        func slot(containing offset: TimeInterval) -> Int {
            var low = 0
            var high = starts.count - 1
            while low < high {
                let mid = (low + high + 1) / 2
                if starts[mid] <= offset { low = mid } else { high = mid - 1 }
            }
            return low
        }
    }

    /// The page whose programs cover `offset`, simulating forward as needed.
    private func page(containing offset: TimeInterval) -> Int {
        while pageStarts.isEmpty || (pageStarts.last ?? .zero) <= offset {
            _ = page(pageStarts.count)
        }
        var low = 0
        var high = pageStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if pageStarts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }

    private func page(_ number: Int) -> Page {
        if let cached = pages[number] {
            return cached
        }
        // Continue from the nearest earlier checkpoint (or the epoch).
        let start = checkpoints.keys.filter { $0 <= number }.max()
        var state = start.flatMap { checkpoints[$0] } ?? State.initial(shows: shows, plan: plan, seed: seed)
        var current = start ?? 0
        var built: Page?
        while current <= number {
            if checkpoints[current] == nil {
                checkpoints[current] = state
                trimCheckpoints(keeping: number)
            }
            if current == pageStarts.count {
                pageStarts.append(state.offset)
            }
            let page = simulatePage(&state)
            if current == number {
                built = page
            }
            current += 1
        }
        if checkpoints[current] == nil {
            checkpoints[current] = state
        }
        if current == pageStarts.count {
            pageStarts.append(state.offset)
        }
        let result = built ?? Page(order: [], starts: [])
        pages[number] = result
        pageRecency.removeAll { $0 == number }
        pageRecency.append(number)
        while pageRecency.count > Tuning.cachedPages {
            pages[pageRecency.removeFirst()] = nil
        }
        return result
    }

    private func trimCheckpoints(keeping number: Int) {
        guard checkpoints.count > Tuning.cachedCheckpoints else { return }
        // Keep the epoch and the checkpoints nearest the page in demand.
        let keep = Set(checkpoints.keys.sorted { abs($0 - number) < abs($1 - number) }.prefix(Tuning.cachedCheckpoints - 1)).union([0])
        checkpoints = checkpoints.filter { keep.contains($0.key) }
    }

    private func simulatePage(_ state: inout State) -> Page {
        var order: [Int] = []
        var starts: [TimeInterval] = []
        order.reserveCapacity(Tuning.programsPerPage)
        starts.reserveCapacity(Tuning.programsPerPage)
        while order.count < Tuning.programsPerPage {
            let item = state.next(shows: shows, plan: plan, seed: seed)
            order.append(item)
            starts.append(state.offset)
            state.offset += max(slotLengths[item], ScheduleConstants.minimumProgramDuration)
        }
        return Page(order: order, starts: starts)
    }

    // MARK: - State

    /// Everything needed to continue the schedule from one moment.
    private struct State {
        var offset: TimeInterval = .zero
        /// Next episode of every show.
        var episode: [Int]
        /// Show on the air in each slot, and episodes it has aired this stint.
        var slotShow: [Int]
        var slotAired: [Int]
        /// Slots each show currently holds (a long show can fill in for a second slot).
        var onAir: [Int]
        /// Slot whose turn it is, episodes aired this turn, and the round number.
        var turnSlot = 0
        var turnAired = 0
        var round = 0
        var roundOrder: [Int]
        /// When each show last aired, and until when a finished show rests.
        var lastAired: [TimeInterval]
        var restingUntil: [TimeInterval]
        /// Fixed tie-break between shows that have waited equally long.
        let rank: [Int]

        static func initial(shows: [[Int]], plan: Plan, seed: UInt64) -> State {
            var generator = SeededGenerator(seed: seed)
            let permutation = Array(0..<shows.count).shuffled(using: &generator)
            var rank = Array(repeating: 0, count: shows.count)
            for (position, show) in permutation.enumerated() {
                rank[show] = position
            }
            let never = -TimeInterval.greatestFiniteMagnitude
            var state = State(
                episode: Array(repeating: 0, count: shows.count),
                slotShow: [], slotAired: [], onAir: Array(repeating: 0, count: shows.count),
                roundOrder: Array(0..<plan.slots),
                lastAired: Array(repeating: never, count: shows.count),
                restingUntil: Array(repeating: never, count: shows.count),
                rank: rank
            )
            for _ in 0..<plan.slots {
                let show = state.nextFromPool(showCount: shows.count, seed: seed)
                state.slotShow.append(show)
                state.slotAired.append(0)
                state.onAir[show] += 1
            }
            state.roundOrder = Self.roundOrder(slots: plan.slots, round: 0, shuffled: plan.shufflesTurns, seed: seed)
            return state
        }

        /// Airs the next episode and advances turns, stints and the pool.
        mutating func next(shows: [[Int]], plan: Plan, seed: UInt64) -> Int {
            let slot = roundOrder[turnSlot]
            let show = slotShow[slot]
            let item = shows[show][episode[show]]
            episode[show] += 1
            slotAired[slot] += 1
            turnAired += 1

            let finished = episode[show] >= shows[show].count
            let stintOver = plan.episodesPerStint.map { slotAired[slot] >= $0 } ?? false
            lastAired[show] = offset
            if finished {
                episode[show] = 0
                restingUntil[show] = offset + Tuning.restAfterFinishing
            }
            if finished || stintOver {
                onAir[show] -= 1
                // A stint that ends with every waiting show still resting just
                // continues: better more of a long show than an early rerun.
                let replacement = finished || hasRestedShow(showCount: shows.count)
                    ? nextFromPool(showCount: shows.count, seed: seed, fallback: show)
                    : show
                slotShow[slot] = replacement
                slotAired[slot] = 0
                onAir[replacement] += 1
            }
            if finished || stintOver || turnAired >= plan.episodesPerTurn {
                turnAired = 0
                turnSlot += 1
                if turnSlot >= roundOrder.count {
                    turnSlot = 0
                    round += 1
                    roundOrder = Self.roundOrder(slots: plan.slots, round: round, shuffled: plan.shufflesTurns, seed: seed)
                }
            }
            return item
        }

        func hasRestedShow(showCount: Int) -> Bool {
            (0..<showCount).contains { onAir[$0] == 0 && restingUntil[$0] <= offset }
        }

        /// The show off the air that has waited longest, skipping finished shows
        /// still resting, unless every show is resting (small pools), in which
        /// case the one whose rest ends first comes back.
        mutating func nextFromPool(showCount: Int, seed: UInt64, fallback: Int? = nil) -> Int {
            var best: Int?
            var soonestRested: Int?
            for show in 0..<showCount where onAir[show] == 0 {
                if restingUntil[show] > offset {
                    if soonestRested.map({ restingUntil[show] < restingUntil[$0] }) ?? true {
                        soonestRested = show
                    }
                    continue
                }
                if let current = best {
                    if lastAired[show] < lastAired[current] || (lastAired[show] == lastAired[current] && rank[show] < rank[current]) {
                        best = show
                    }
                } else {
                    best = show
                }
            }
            return best ?? soonestRested ?? fallback ?? 0
        }

        static func roundOrder(slots: Int, round: Int, shuffled: Bool, seed: UInt64) -> [Int] {
            guard shuffled else { return Array(0..<slots) }
            var generator = SeededGenerator(seed: seed ^ StableHash.fnv1a("round\(round)"))
            return Array(0..<slots).shuffled(using: &generator)
        }
    }

    // MARK: - Shows

    /// Item indices grouped by show (movies stand alone), in broadcast order
    /// with specials last, shows sorted by id so the schedule is stable.
    private static func groupedByShow(_ items: [MediaItem]) -> [[Int]] {
        var groups: [String: [Int]] = [:]
        for index in items.indices where items[index].duration > .zero {
            groups[items[index].seriesID ?? items[index].id, default: []].append(index)
        }
        return groups.sorted { $0.key < $1.key }.map { _, indices in
            indices.sorted { lhs, rhs in
                let left = items[lhs].series?.broadcastOrder ?? (.zero, .zero)
                let right = items[rhs].series?.broadcastOrder ?? (.zero, .zero)
                return left != right ? left < right : items[lhs].id < items[rhs].id
            }
        }
    }
}
