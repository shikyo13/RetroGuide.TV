import Foundation

/// A channel's running order, as arithmetic: the program at any position
/// and when it starts, found in the same time in any year. Channels air
/// their order as it is unless a clash makes them step around (see
/// ``TrackingPicker``).
protocol NominalOrder: Sendable {
    /// Milliseconds from the epoch until program `position` starts.
    func start(of position: Int) -> Int
    /// The show (index into ``ScheduleContext/shows``) and channel item of program `position`.
    func program(at position: Int) -> (show: Int, item: Int)
    /// The position of the program airing `offset` milliseconds after the epoch.
    func position(at offset: Int) -> Int
}

enum NominalOrders {
    /// Rotation needs depth: enough content and enough shows waiting that a
    /// finished show can always rest. Smaller channels, and Shuffle, air
    /// everything once in a fixed order before anything repeats (``CycleOrder``).
    enum Tuning {
        static let minimumContent: TimeInterval = 28 * 24 * ScheduleConstants.secondsPerHour
        static let minimumShows = 6
    }

    /// The order a channel runs with `ordering`: a rotating lineup when it
    /// has the depth for one, otherwise one fixed cycle after another.
    /// - Parameter keep: how often each show takes its turns on a cycling
    ///   channel (``ShowBudget``); always when nil.
    static func make(ordering: ScheduleOrdering, context: ScheduleContext, keep: [Int]? = nil) -> any NominalOrder {
        guard rotates(ordering: ordering, items: context.items) else {
            return CycleOrder(ordering: ordering, context: context, keep: keep)
        }
        return LaneOrder(ordering: ordering, context: context)
    }

    static func rotates(ordering: ScheduleOrdering, items: [MediaItem]) -> Bool {
        let titles = Set(items.map(\.showID)).count
        guard ordering != .shuffle, titles > 1 else { return false }
        guard ordering != .marathon else { return true }
        let content = items.reduce(TimeInterval.zero) { $0 + $1.duration }
        return content >= Tuning.minimumContent && titles >= Tuning.minimumShows
    }

    /// Largest `n` in `0...upper` with `value(n) <= target`, for nondecreasing `value`.
    static func lastNotAfter(_ target: Int, upper: Int, value: (Int) -> Int) -> Int {
        var low = 0
        var high = max(upper, 0)
        while low < high {
            let middle = low + (high - low + 1) / 2
            if value(middle) <= target {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low
    }
}

/// Shows in turns, cycle after cycle. Every show gets the same number of
/// turns per cycle whatever its episode count (a 500-episode show just takes
/// longer to get through), and each turn airs that show's next episode, in
/// order. Show Rotation is one turn per show in a fixed order; Shuffle a new
/// random order of shows each round; Block Shuffle the same with a short
/// block of episodes per turn; Marathon every episode of a show, then the
/// next show.
struct CycleOrder: NominalOrder {
    enum Tuning {
        /// Rounds of different random show orders per Shuffle and Block Shuffle
        /// cycle, so the pattern of shows doesn't visibly repeat every round.
        static let shuffledRounds = 8
    }

    /// Show indices in airing order: a turn airs that show's next episode.
    private let turns: [Int]
    /// Earlier turns of the same show within the cycle, per turn.
    private let occurrence: [Int]
    /// Turns per show per cycle.
    private let perCycle: [Int]
    private let reels: [ShowReel]
    /// In how many of every ``ShowBudget/Tuning/cycles`` cycles each show
    /// takes its turns, and where in that pattern it starts.
    private let keep: [Int]
    private let phase: [Int]
    /// Lower bounds on how fast positions and airtime build up per cycle.
    private let positionRate: Int
    private let positionSlack: Int
    private let timeRate: Int
    private let timeSlack: Int

    /// - Parameter keep: per show, in how many of every ``ShowBudget/Tuning/cycles``
    ///   cycles it takes its turns (``ShowBudget``); every cycle when nil.
    init(ordering: ScheduleOrdering, context: ScheduleContext, keep: [Int]? = nil) {
        turns = Self.turns(for: ordering, context: context)
        var seen = Array(repeating: 0, count: context.shows.count)
        var occurrence: [Int] = []
        occurrence.reserveCapacity(turns.count)
        for show in turns {
            occurrence.append(seen[show])
            seen[show] += 1
        }
        self.occurrence = occurrence
        perCycle = seen
        reels = context.shows.indices.map { show in
            ShowReel(items: context.shows[show], slotLengths: context.slotLengths, start: context.firstEpisode(of: show))
        }
        let cycles = ShowBudget.Tuning.cycles
        let keep = keep ?? Array(repeating: cycles, count: context.shows.count)
        self.keep = keep
        phase = context.showIDs.map { Int(StableHash.fnv1a($0) % UInt64(cycles)) }
        let shortest = reels.map { reel in reel.items.map { context.slotLengths[$0] }.min() ?? .zero }
        positionRate = max(1, zip(seen, keep).reduce(0) { $0 + $1.0 * $1.1 })
        positionSlack = seen.reduce(0, +)
        timeRate = max(1, seen.indices.reduce(0) { $0 + seen[$1] * keep[$1] * shortest[$1] })
        timeSlack = seen.indices.reduce(0) { $0 + seen[$1] * shortest[$1] }
    }

    /// One cycle of turns for `ordering`.
    static func turns(for ordering: ScheduleOrdering, context: ScheduleContext) -> [Int] {
        let shows = Array(context.shows.indices)
        var generator = SeededGenerator(seed: context.seed)
        switch ordering {
        case .syndication:
            return shows.shuffled(using: &generator)
        case .shuffle:
            return rounds(of: shows, repeating: 1, using: &generator)
        case .blockShuffle:
            return rounds(of: shows, repeating: ScheduleConstants.blockShuffleEpisodesPerBlock, using: &generator)
        case .marathon:
            return shows.flatMap { Array(repeating: $0, count: context.shows[$0].count) }
        }
    }

    /// ``Tuning/shuffledRounds`` rounds, each every show once in a new random
    /// order (each turn `repeating` times in a row), never the same show
    /// either side of a round boundary when there's a choice.
    private static func rounds(of shows: [Int], repeating: Int, using generator: inout SeededGenerator) -> [Int] {
        var order: [Int] = []
        for _ in 0..<Tuning.shuffledRounds {
            var round = shows.shuffled(using: &generator)
            if round.count > 1, round.first == order.last {
                round.swapAt(0, round.count - 1)
            }
            order += round
        }
        return order.flatMap { Array(repeating: $0, count: repeating) }
    }

    func start(of position: Int) -> Int {
        let cycle = cycle(containingPosition: position)
        var offset = cycleStart(cycle)
        var remaining = position - positions(before: cycle)
        for turn in turns.indices where remaining > 0 && takesTurns(turns[turn], in: cycle) {
            offset += slotLength(cycle: cycle, turn: turn)
            remaining -= 1
        }
        return offset
    }

    func program(at position: Int) -> (show: Int, item: Int) {
        let cycle = cycle(containingPosition: position)
        let turn = turn(at: position - positions(before: cycle), in: cycle)
        let show = turns[turn]
        return (show, reels[show].item(ofAiring: airings(of: show, before: cycle) + occurrence[turn]))
    }

    func position(at offset: Int) -> Int {
        let upper = max(0, (offset + timeSlack) * ShowBudget.Tuning.cycles / timeRate + 1)
        let cycle = NominalOrders.lastNotAfter(offset, upper: upper, value: cycleStart)
        var time = cycleStart(cycle)
        var position = positions(before: cycle)
        for turn in turns.indices where takesTurns(turns[turn], in: cycle) {
            time += slotLength(cycle: cycle, turn: turn)
            if time > offset {
                return position
            }
            position += 1
        }
        return position
    }

    // MARK: - Cycles

    /// Cycles before `cycle` in which `show` took its turns.
    private func cyclesTaken(by show: Int, before cycle: Int) -> Int {
        let cycles = ShowBudget.Tuning.cycles
        return (max(cycle, 0) + phase[show]) * keep[show] / cycles - phase[show] * keep[show] / cycles
    }

    private func takesTurns(_ show: Int, in cycle: Int) -> Bool {
        cyclesTaken(by: show, before: cycle + 1) > cyclesTaken(by: show, before: cycle)
    }

    private func airings(of show: Int, before cycle: Int) -> Int {
        perCycle[show] * cyclesTaken(by: show, before: cycle)
    }

    private func positions(before cycle: Int) -> Int {
        perCycle.indices.reduce(0) { $0 + airings(of: $1, before: cycle) }
    }

    private func cycleStart(_ cycle: Int) -> Int {
        reels.indices.reduce(.zero) { $0 + reels[$1].airtime(airings(of: $1, before: cycle)) }
    }

    private func cycle(containingPosition position: Int) -> Int {
        let upper = max(0, (position + positionSlack) * ShowBudget.Tuning.cycles / positionRate + 1)
        return NominalOrders.lastNotAfter(position, upper: upper, value: positions(before:))
    }

    /// The turn of `cycle` that is its `index`th program.
    private func turn(at index: Int, in cycle: Int) -> Int {
        var remaining = index
        for turn in turns.indices where takesTurns(turns[turn], in: cycle) {
            if remaining == 0 {
                return turn
            }
            remaining -= 1
        }
        preconditionFailure("position past the end of its cycle")
    }

    private func slotLength(cycle: Int, turn: Int) -> Int {
        let show = turns[turn]
        let airing = airings(of: show, before: cycle) + occurrence[turn]
        return reels[show].airtime(airing + 1) - reels[show].airtime(airing)
    }
}

/// A channel run the way a real network runs a lineup. A few lanes are on
/// the air at once, taking turns; each lane runs its shows one run at a
/// time (about a season, or the rest of the show), continuing each where it
/// left off, so a show can be followed day to day like Bleach on Toonami,
/// every show gets its turn, and a finished show rests while the others in
/// its lane have theirs.
struct LaneOrder: NominalOrder {
    enum Tuning {
        /// Shows on the air at once.
        static let lanes = 6
        /// Shows per lane, so a finished show always rests.
        static let showsPerLane = 3
        /// About one TV season.
        static let episodesPerRun = 26
    }

    /// One show in a lane: its runs split a pass of its episodes into
    /// near-equal pieces, counted from where the channel starts the show.
    private struct LaneShow: Sendable {
        let show: Int
        let reel: ShowReel
        let pieces: Int

        /// Airings in this show's first `runs` runs.
        func airings(beforeRun runs: Int) -> Int {
            (runs / pieces) * reel.count + (runs % pieces) * reel.count / pieces
        }

        func runLength(_ run: Int) -> Int {
            airings(beforeRun: run + 1) - airings(beforeRun: run)
        }
    }

    private let lanes: [[LaneShow]]
    /// Episodes a lane airs per turn, and whether the lanes' turns are reshuffled each round.
    private let episodesPerTurn: Int
    private let shufflesTurns: Bool
    private let seed: UInt64
    private let shortestRound: Int

    init(ordering: ScheduleOrdering, context: ScheduleContext) {
        let showCount = context.shows.count
        let isMarathon = ordering == .marathon
        let laneCount = isMarathon ? 1 : max(1, min(Tuning.lanes, max(2, showCount / Tuning.showsPerLane), showCount))
        episodesPerTurn = ordering == .blockShuffle ? ScheduleConstants.blockShuffleEpisodesPerBlock : 1
        shufflesTurns = ordering == .blockShuffle
        seed = context.seed
        var generator = SeededGenerator(seed: context.seed)
        let order = Array(0..<showCount).shuffled(using: &generator)
        var lanes = Array(repeating: [LaneShow](), count: laneCount)
        for (rank, show) in order.enumerated() {
            let count = context.shows[show].count
            let pieces = isMarathon ? 1 : max(1, (count + Tuning.episodesPerRun - 1) / Tuning.episodesPerRun)
            // Each channel starts every show somewhere different, so channels
            // sharing a show don't move through it in step.
            let reel = ShowReel(items: context.shows[show], slotLengths: context.slotLengths, start: context.firstEpisode(of: show))
            lanes[rank % laneCount].append(LaneShow(show: show, reel: reel, pieces: pieces))
        }
        self.lanes = lanes
        let shortestSlot = context.slotLengths.min() ?? .zero
        shortestRound = laneCount * episodesPerTurn * shortestSlot
    }

    private var programsPerRound: Int {
        lanes.count * episodesPerTurn
    }

    func start(of position: Int) -> Int {
        let round = position / programsPerRound
        var offset = roundStart(round)
        let within = position % programsPerRound
        guard within > .zero else { return offset }
        for step in 0..<within {
            offset += slotLength(round: round, step: step)
        }
        return offset
    }

    func program(at position: Int) -> (show: Int, item: Int) {
        let round = position / programsPerRound
        let (lane, episode) = laneEpisode(round: round, step: position % programsPerRound)
        let (laneShow, airing) = locate(lane: lane, episode: episode)
        return (laneShow.show, laneShow.reel.item(ofAiring: airing))
    }

    func position(at offset: Int) -> Int {
        let upper = shortestRound > .zero ? offset / shortestRound + 1 : 0
        let round = NominalOrders.lastNotAfter(offset, upper: upper, value: roundStart)
        var time = roundStart(round)
        for step in 0..<programsPerRound {
            let next = time + slotLength(round: round, step: step)
            if next > offset {
                return round * programsPerRound + step
            }
            time = next
        }
        return (round + 1) * programsPerRound
    }

    // MARK: - Rounds and lanes

    /// Lane order within a round: fixed, or reshuffled every round.
    private func laneOrder(round: Int) -> [Int] {
        guard shufflesTurns else { return Array(lanes.indices) }
        var generator = SeededGenerator(seed: seed ^ StableHash.fnv1a("round\(round)"))
        return Array(lanes.indices).shuffled(using: &generator)
    }

    /// The lane airing step `step` of `round`, and that lane's episode number.
    private func laneEpisode(round: Int, step: Int) -> (lane: Int, episode: Int) {
        let lane = laneOrder(round: round)[step / episodesPerTurn]
        return (lane, round * episodesPerTurn + step % episodesPerTurn)
    }

    private func roundStart(_ round: Int) -> Int {
        lanes.indices.reduce(.zero) { $0 + laneAirtime(lane: $1, episodes: round * episodesPerTurn) }
    }

    private func slotLength(round: Int, step: Int) -> Int {
        let (lane, episode) = laneEpisode(round: round, step: step)
        let (laneShow, airing) = locate(lane: lane, episode: episode)
        return laneShow.reel.airtime(airing + 1) - laneShow.reel.airtime(airing)
    }

    /// Episodes a lane has aired after `runs` runs of every one of its shows.
    private func laneEpisodes(lane: Int, cycles runs: Int) -> Int {
        lanes[lane].reduce(0) { $0 + $1.airings(beforeRun: runs) }
    }

    /// The lane's cycle (every show one run) containing lane episode `episode`.
    private func cycle(lane: Int, episode: Int) -> Int {
        let upper = episode / max(lanes[lane].count, 1) + 1
        return NominalOrders.lastNotAfter(episode, upper: upper) { laneEpisodes(lane: lane, cycles: $0) }
    }

    /// The show airing a lane's `episode`th episode, and which airing of that show it is.
    private func locate(lane: Int, episode: Int) -> (LaneShow, Int) {
        let shows = lanes[lane]
        let run = cycle(lane: lane, episode: episode)
        var base = laneEpisodes(lane: lane, cycles: run)
        for laneShow in shows {
            let length = laneShow.runLength(run)
            if episode < base + length {
                return (laneShow, laneShow.airings(beforeRun: run) + episode - base)
            }
            base += length
        }
        let last = shows[shows.count - 1]
        return (last, last.airings(beforeRun: run + 1))
    }

    /// Slot time of a lane's first `episodes` episodes.
    private func laneAirtime(lane: Int, episodes: Int) -> Int {
        let shows = lanes[lane]
        guard episodes > .zero, !shows.isEmpty else { return .zero }
        let run = cycle(lane: lane, episode: episodes)
        var base = laneEpisodes(lane: lane, cycles: run)
        var total = 0
        for laneShow in shows {
            let before = laneShow.airings(beforeRun: run)
            let length = laneShow.runLength(run)
            let aired = min(max(episodes - base, 0), length)
            total += laneShow.reel.airtime(before + aired)
            base += length
        }
        return total
    }
}
