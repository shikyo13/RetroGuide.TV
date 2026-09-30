import Foundation

/// Airs a channel's shows in turns, cycle after cycle. Every show gets the same
/// number of turns per cycle whatever its episode count (a 500-episode show
/// just takes longer to get through), and each turn airs that show's next
/// episode, in order. Show Rotation is one turn per show in a fixed order;
/// Shuffle a new random order of shows each round; Block Shuffle the same with
/// a short block of episodes per turn; Marathon every episode of a show, then
/// the next show.
///
/// When the show whose turn it is may not air now (it's on enough other
/// channels), its turn waits and the next show that may air goes early; the
/// turn it took is skipped when the order reaches it. Once the waiting show
/// is free again it alternates with the others rather than airing its backlog
/// back to back. A turn still blocked when nothing else is left this cycle is
/// set aside and made up once its show is free. The order itself never changes.
struct CyclePicker: ProgramPicker {
    enum Tuning {
        /// Set-aside turns remembered for making up; past this the oldest is
        /// dropped (a show blocked that long airs elsewhere anyway).
        static let maximumSetAside = 32
        /// Rounds of different random show orders per Shuffle and Block Shuffle
        /// cycle, so the pattern of shows doesn't visibly repeat every round.
        static let shuffledRounds = 8
    }

    /// Show indices in airing order: a turn airs that show's next episode.
    private let turns: [Int]
    /// The turn due next.
    private var position = 0
    /// Turns that already aired out of order (early, or made up late), so
    /// the order skips them next time it reaches them.
    private var airedEarly: [Bool]
    /// Turns set aside while their show was blocked, oldest first.
    private var setAside: [Int] = []
    private var lastShow: Int?
    /// Next episode of every show, when following episodes.
    private var episode: [Int]

    init(ordering: ScheduleOrdering, context: ScheduleContext) {
        turns = Self.turns(for: ordering, context: context)
        airedEarly = Array(repeating: false, count: turns.count)
        episode = Array(repeating: 0, count: context.shows.count)
    }

    mutating func next(at offset: TimeInterval, in context: ScheduleContext, isAllowed: (Int) -> Bool) -> Int {
        for _ in 0...turns.count {
            skipTurnsAiredEarly()
            let due = candidate(at: position, in: context)
            let dueShow = context.showOfItem[due]
            let dueIsAllowed = isAllowed(due)
            // Back to back only where the order means it (a block of episodes).
            let isRepeat = dueShow == lastShow && show(ofTurn: position - 1, in: context) != dueShow
            if dueIsAllowed, !isRepeat {
                return takeDueTurn(due, in: context)
            }
            if let (index, item) = firstSetAsideAllowed(in: context, isAllowed: isAllowed) {
                airedEarly[setAside.remove(at: index)] = true
                return take(item, in: context)
            }
            if let (turn, item) = firstAllowedAhead(avoiding: isRepeat ? dueShow : nil, in: context, isAllowed: isAllowed) {
                airedEarly[turn] = true
                return take(item, in: context)
            }
            if dueIsAllowed {
                return takeDueTurn(due, in: context)
            }
            // Every other turn left this cycle is blocked or already aired:
            // set the blocked one aside and move on.
            setAside.append(position)
            if setAside.count > Tuning.maximumSetAside {
                setAside.removeFirst()
            }
            position = (position + 1) % turns.count
        }
        // Nothing may air: better a simulcast than dead air.
        skipTurnsAiredEarly()
        return takeDueTurn(candidate(at: position, in: context), in: context)
    }

    private mutating func skipTurnsAiredEarly() {
        while airedEarly[position] {
            airedEarly[position] = false
            position = (position + 1) % turns.count
        }
    }

    /// The oldest set-aside turn that may air now, unless its show just aired.
    private func firstSetAsideAllowed(in context: ScheduleContext, isAllowed: (Int) -> Bool) -> (index: Int, item: Int)? {
        for (index, turn) in setAside.enumerated() {
            let item = candidate(at: turn, in: context)
            if context.showOfItem[item] != lastShow, isAllowed(item) {
                return (index, item)
            }
        }
        return nil
    }

    /// The nearest turn left this cycle whose show may air.
    private func firstAllowedAhead(avoiding avoided: Int?, in context: ScheduleContext, isAllowed: (Int) -> Bool) -> (turn: Int, item: Int)? {
        // Usually a handful of shows: a list beats hashing.
        var blocked: [Int] = avoided.map { [$0] } ?? []
        for turn in (position + 1)..<turns.count where !airedEarly[turn] {
            let item = candidate(at: turn, in: context)
            let show = context.showOfItem[item]
            guard !blocked.contains(show) else { continue }
            if isAllowed(item) {
                return (turn, item)
            }
            // Blocking is per show: no need to ask about its other turns.
            blocked.append(show)
        }
        return nil
    }

    private func show(ofTurn turn: Int, in context: ScheduleContext) -> Int {
        turns[(turn + turns.count) % turns.count]
    }

    private func candidate(at turn: Int, in context: ScheduleContext) -> Int {
        let show = turns[turn]
        return context.shows[show][episode[show]]
    }

    /// One cycle of turns for `ordering`.
    private static func turns(for ordering: ScheduleOrdering, context: ScheduleContext) -> [Int] {
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

    private mutating func takeDueTurn(_ item: Int, in context: ScheduleContext) -> Int {
        position = (position + 1) % turns.count
        return take(item, in: context)
    }

    private mutating func take(_ item: Int, in context: ScheduleContext) -> Int {
        let show = context.showOfItem[item]
        episode[show] = (episode[show] + 1) % context.shows[show].count
        lastShow = show
        return item
    }
}
