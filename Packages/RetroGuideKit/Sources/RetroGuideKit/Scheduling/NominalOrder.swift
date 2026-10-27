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

/// Where a channel's order stands at one moment, by identity rather than by
/// position, so the next version of its content can carry on from exactly
/// there: every show's next episode, which turn is due, and what each lane
/// is running.
struct SpliceState: Sendable {
    /// Each show's last aired episode (item index): the new content decides
    /// what follows it, so an episode added after the last one airs next
    /// rather than the show starting over.
    var lastAired: [Int: Int] = [:]
    /// Cycling orders: the turns from the due one on, as (show, occurrence in the cycle).
    var upcomingTurns: [Turn] = []
    /// Rotating orders: each lane's shows, the one on the air first, and the lane due next.
    var lanes: [[Int]] = []
    var dueLane = 0

    struct Turn: Sendable, Hashable {
        let show: Int
        let occurrence: Int
    }
}

/// One version of a channel's order, measured from where it starts
/// (position and time zero), able to say where it stands at any position.
protocol OrderSegment: NominalOrder {
    func state(at position: Int) -> SpliceState
}

enum NominalOrders {
    /// Rotation needs depth: enough content and enough shows waiting that a
    /// finished show can always rest. Smaller channels, and Shuffle, air
    /// everything once in a fixed order before anything repeats (``CycleSegment``).
    enum Tuning {
        static let minimumContent: TimeInterval = 28 * 24 * ScheduleConstants.secondsPerHour
        static let minimumShows = 6
    }

    /// The order a channel runs with `ordering`. Each time its content
    /// changes (``ScheduleContext/versionTimes``) or its show budget does,
    /// the order carries on from where it stood with the new content, so the
    /// schedule before that moment never changes and nothing skips or repeats.
    static func make(ordering: ScheduleOrdering, context: ScheduleContext, budget: BudgetSchedule? = nil) -> any NominalOrder {
        CompositeOrder.build(ordering: ordering, context: context, budget: budget)
    }

    static func rotates(ordering: ScheduleOrdering, items: [MediaItem]) -> Bool {
        let titles = Set(items.map(\.showID)).count
        let content = items.reduce(TimeInterval.zero) { $0 + $1.duration }
        return rotates(ordering: ordering, titles: titles, content: content)
    }

    static func rotates(ordering: ScheduleOrdering, titles: Int, content: TimeInterval) -> Bool {
        guard ordering != .shuffle, titles > 1 else { return false }
        guard ordering != .marathon else { return true }
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

/// Each show's episodes as of one content version, with their slot-time
/// prefix sums, rebuilt only for shows whose episodes changed.
struct EpisodeShelf {
    private let context: ScheduleContext
    /// Item indices joining at each version time.
    private let joining: [Int: [Int]]
    private(set) var episodes: [Int: [Int]] = [:]
    private(set) var prefixes: [Int: [Int]] = [:]
    /// Shows with episodes so far, ascending.
    private(set) var shows: [Int] = []
    private(set) var content: TimeInterval = .zero

    init(context: ScheduleContext) {
        self.context = context
        var joining: [Int: [Int]] = [:]
        for show in context.shows.indices {
            for item in context.shows[show] {
                joining[context.effective[item], default: []].append(item)
            }
        }
        self.joining = joining
    }

    /// Takes in the items joining at `time`.
    mutating func advance(to time: Int) {
        guard let items = joining[time] else { return }
        var changed = Set<Int>()
        for item in items {
            changed.insert(context.showOfItem[item])
            content += context.items[item].duration
        }
        for show in changed {
            // Broadcast order, the same as the show's full list.
            let list = context.shows[show].filter { context.effective[$0] <= time }
            episodes[show] = list
            prefixes[show] = ShowReel.prefix(of: list, slotLengths: context.slotLengths)
        }
        shows = episodes.keys.sorted()
    }

    /// The show's reel, starting after `previous` (its last aired episode),
    /// or where the channel starts the show when it's new.
    func reel(of show: Int, after previous: Int?) -> ShowReel {
        let items = episodes[show] ?? []
        let start = previous.flatMap { items.firstIndex(of: $0) }.map { $0 + 1 } ?? context.firstEpisode(of: show, count: items.count)
        return ShowReel(items: items, prefix: prefixes[show] ?? [0], start: start)
    }
}

/// Shows in turns, cycle after cycle. Every show gets the same number of
/// turns per cycle whatever its episode count (a 500-episode show just takes
/// longer to get through), and each turn airs that show's next episode, in
/// order. Show Rotation is one turn per show in a fixed order; Shuffle a new
/// random order of shows each round; Block Shuffle the same with a short
/// block of episodes per turn; Marathon every episode of a show, then the
/// next show. The order of shows comes from each show's own identity, so a
/// show joining or leaving doesn't move the others.
struct CycleSegment: OrderSegment {
    enum Tuning {
        /// Rounds of different random show orders per Shuffle and Block Shuffle
        /// cycle, so the pattern of shows doesn't visibly repeat every round.
        static let shuffledRounds = 8
    }

    /// One cycle's turns for a set of shows, kept for the next version when
    /// only episodes changed (the usual case), since the order of shows
    /// depends only on which shows there are.
    struct Template: Sendable {
        let shows: [Int]
        let canonical: [Int]
        let canonicalOccurrence: [Int]
        let perCycle: [Int]
    }

    /// The turn template, for the next version to reuse.
    let template: Template
    /// The channel's show index of each local show.
    private let shows: [Int]
    /// Turns in airing order (local show indices), starting with the one due.
    private let turns: [Int]
    /// Earlier turns of the same show in this segment's cycle, and in the canonical one.
    private let occurrence: [Int]
    private let canonicalOccurrence: [Int]
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

    init(ordering: ScheduleOrdering, context: ScheduleContext, shelf: EpisodeShelf, keep budget: [Int]?, from state: SpliceState?, reusing previous: Template? = nil) {
        let shows = shelf.shows
        self.shows = shows
        var local: [Int: Int] = [:]
        for (index, show) in shows.enumerated() {
            local[show] = index
        }
        let template: Template
        if let previous, previous.shows == shows, ordering != .marathon {
            template = previous
        } else {
            let canonical = Self.turns(for: ordering, context: context, shows: shows, shelf: shelf).map { local[$0] ?? 0 }
            var seen = Array(repeating: 0, count: shows.count)
            var canonicalOccurrence: [Int] = []
            canonicalOccurrence.reserveCapacity(canonical.count)
            for show in canonical {
                canonicalOccurrence.append(seen[show])
                seen[show] += 1
            }
            template = Template(shows: shows, canonical: canonical, canonicalOccurrence: canonicalOccurrence, perCycle: seen)
        }
        self.template = template
        let canonical = template.canonical
        let canonicalOccurrence = template.canonicalOccurrence
        let seen = template.perCycle
        perCycle = seen
        // Carry on from the turn that was due (or the next one still here).
        var rotation = 0
        if let state {
            for turn in state.upcomingTurns {
                guard let show = local[turn.show], seen[show] > 0 else { continue }
                let occurrence = min(turn.occurrence, seen[show] - 1)
                rotation = canonical.indices.first { canonical[$0] == show && canonicalOccurrence[$0] == occurrence } ?? 0
                break
            }
        }
        turns = Array(canonical[rotation...] + canonical[..<rotation])
        self.canonicalOccurrence = Array(canonicalOccurrence[rotation...] + canonicalOccurrence[..<rotation])
        var rotatedSeen = Array(repeating: 0, count: shows.count)
        var occurrence: [Int] = []
        occurrence.reserveCapacity(turns.count)
        for show in turns {
            occurrence.append(rotatedSeen[show])
            rotatedSeen[show] += 1
        }
        self.occurrence = occurrence
        reels = shows.map { shelf.reel(of: $0, after: state?.lastAired[$0]) }
        let cycles = ShowBudget.Tuning.cycles
        let keep = shows.map { budget?[$0] ?? cycles }
        self.keep = keep
        phase = shows.map { Int(StableHash.fnv1a(context.showIDs[$0]) % UInt64(cycles)) }
        let shortest = shows.map { context.shortestSlot[$0] }
        positionRate = max(1, zip(seen, keep).reduce(0) { $0 + $1.0 * $1.1 })
        positionSlack = seen.reduce(0, +)
        timeRate = max(1, seen.indices.reduce(0) { $0 + seen[$1] * keep[$1] * shortest[$1] })
        timeSlack = seen.indices.reduce(0) { $0 + seen[$1] * shortest[$1] }
    }

    /// One cycle of turns for `ordering` (channel show indices), ordered by
    /// each show's identity.
    static func turns(for ordering: ScheduleOrdering, context: ScheduleContext, shows: [Int], shelf: EpisodeShelf) -> [Int] {
        func ranked(_ salt: String) -> [Int] {
            let rank = context.ranks(salt: salt)
            return shows.sorted { rank[$0] < rank[$1] }
        }
        switch ordering {
        case .syndication:
            return ranked("")
        case .shuffle:
            return rounds(of: ranked, repeating: 1)
        case .blockShuffle:
            return rounds(of: ranked, repeating: ScheduleConstants.blockShuffleEpisodesPerBlock)
        case .marathon:
            return ranked("").flatMap { Array(repeating: $0, count: shelf.episodes[$0]?.count ?? 0) }
        }
    }

    /// ``Tuning/shuffledRounds`` rounds, each every show once in a new order
    /// (each turn `repeating` times in a row), never the same show either side
    /// of a round boundary when there's a choice.
    private static func rounds(of ranked: (String) -> [Int], repeating: Int) -> [Int] {
        var order: [Int] = []
        for round in 0..<Tuning.shuffledRounds {
            var shows = ranked("round\(round)")
            if shows.count > 1, shows.first == order.last {
                shows.swapAt(0, shows.count - 1)
            }
            order += shows
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
        return (shows[show], reels[show].item(ofAiring: airings(of: show, before: cycle) + occurrence[turn]))
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

    func state(at position: Int) -> SpliceState {
        let cycle = cycle(containingPosition: position)
        var aired = shows.indices.map { airings(of: $0, before: cycle) }
        var remaining = position - positions(before: cycle)
        var due = 0
        for turn in turns.indices where takesTurns(turns[turn], in: cycle) {
            if remaining == 0 {
                due = turn
                break
            }
            aired[turns[turn]] += 1
            remaining -= 1
        }
        var state = SpliceState()
        for index in shows.indices {
            state.lastAired[shows[index]] = reels[index].item(beforeAiring: aired[index])
        }
        // Enough turns to find one whose show is still there after a change.
        let kept = min(turns.count, 4 * shows.count + 64)
        state.upcomingTurns = ((0..<kept).map { (due + $0) % turns.count }).map {
            SpliceState.Turn(show: shows[turns[$0]], occurrence: canonicalOccurrence[$0])
        }
        return state
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
/// its lane have theirs. When content changes, every show keeps its lane; a
/// new show joins the lightest lane, right after the show on the air there.
struct LaneSegment: OrderSegment {
    enum Tuning {
        /// Shows on the air at once.
        static let lanes = 6
        /// Shows per lane, so a finished show always rests.
        static let showsPerLane = 3
        /// About one TV season.
        static let episodesPerRun = 26
    }

    /// One show in a lane: its runs split a pass of its episodes into
    /// near-equal pieces, counted from where the lane picks it up.
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

    init(ordering: ScheduleOrdering, context: ScheduleContext, shelf: EpisodeShelf, from state: SpliceState?) {
        let present = shelf.shows
        let isMarathon = ordering == .marathon
        let target = isMarathon ? 1 : max(1, min(Tuning.lanes, max(2, present.count / Tuning.showsPerLane), present.count))
        episodesPerTurn = ordering == .blockShuffle ? ScheduleConstants.blockShuffleEpisodesPerBlock : 1
        shufflesTurns = ordering == .blockShuffle
        seed = context.seed
        let presentSet = Set(present)
        let rank = context.ranks()
        let byRank = present.sorted { rank[$0] < rank[$1] }
        var laneShows: [[Int]]
        var dueLane = 0
        if let state, !state.lanes.isEmpty {
            // Every show stays in its lane; new shows join the lightest lane
            // right after the show on the air there; empty lanes go.
            laneShows = state.lanes.map { $0.filter(presentSet.contains) }
            if isMarathon, laneShows.count > 1 {
                laneShows = [laneShows.flatMap { $0 }]
            }
            while laneShows.count < target {
                laneShows.append([])
            }
            let placed = Set(laneShows.joined())
            func load(_ lane: [Int]) -> Int {
                lane.reduce(0) { $0 + (shelf.prefixes[$1]?.last ?? 0) }
            }
            for show in byRank where !placed.contains(show) {
                let lane = laneShows.indices.min { load(laneShows[$0]) < load(laneShows[$1]) } ?? 0
                laneShows[lane].insert(show, at: min(1, laneShows[lane].count))
            }
            let kept = laneShows.indices.filter { !laneShows[$0].isEmpty }
            let due = kept.first { $0 >= state.dueLane } ?? kept.first ?? 0
            laneShows = kept.map { laneShows[$0] }
            dueLane = kept.firstIndex(of: due) ?? 0
        } else {
            laneShows = Array(repeating: [], count: target)
            for (rank, show) in byRank.enumerated() {
                laneShows[rank % target].append(show)
            }
        }
        // The lane due next goes first.
        let rotated = Array(laneShows[dueLane...] + laneShows[..<dueLane])
        lanes = rotated.map { lane in
            lane.map { show in
                let reel = shelf.reel(of: show, after: state?.lastAired[show])
                let pieces = isMarathon ? 1 : max(1, (reel.count + Tuning.episodesPerRun - 1) / Tuning.episodesPerRun)
                return LaneShow(show: show, reel: reel, pieces: pieces)
            }
        }
        let shortestSlot = present.map { context.shortestSlot[$0] }.min() ?? .zero
        shortestRound = lanes.count * episodesPerTurn * shortestSlot
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

    func state(at position: Int) -> SpliceState {
        let round = position / programsPerRound
        let step = position % programsPerRound
        let order = laneOrder(round: round)
        let turn = step / episodesPerTurn
        var state = SpliceState()
        state.dueLane = order[turn]
        state.lanes = lanes.indices.map { lane in
            // Episodes this lane has aired before `position`.
            let slot = order.firstIndex(of: lane) ?? 0
            let extra = slot < turn ? episodesPerTurn : (slot == turn ? step % episodesPerTurn : 0)
            let episode = round * episodesPerTurn + extra
            let shows = lanes[lane]
            let run = cycle(lane: lane, episode: episode)
            var base = laneEpisodes(lane: lane, cycles: run)
            var current = shows.count - 1
            for (index, laneShow) in shows.enumerated() {
                let length = laneShow.runLength(run)
                if episode < base + length {
                    current = index
                    break
                }
                base += length
            }
            for (index, laneShow) in shows.enumerated() {
                let aired: Int
                if index < current {
                    aired = laneShow.airings(beforeRun: run + 1)
                } else if index > current {
                    aired = laneShow.airings(beforeRun: run)
                } else {
                    aired = laneShow.airings(beforeRun: run) + episode - base
                }
                state.lastAired[laneShow.show] = laneShow.reel.item(beforeAiring: aired)
            }
            return (shows[current...] + shows[..<current]).map(\.show)
        }
        return state
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
