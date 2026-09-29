import Foundation

/// Airs a channel's items in one fixed order, cycle after cycle, so nothing
/// repeats until everything has aired.
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
    }

    /// Item indices in airing order.
    private let turns: [Int]
    /// Whether turns stand for "the show's next episode" (episodic orderings)
    /// rather than a specific item (shuffle).
    private let followsEpisodes: Bool
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
        var generator = SeededGenerator(seed: context.seed)
        let playable = context.shows.flatMap { $0 }.sorted()
        let order = PlaylistArranger.arrange(playable.map { context.items[$0] }, ordering: ordering, using: &generator)
        turns = order.map { playable[$0] }
        followsEpisodes = ordering != .shuffle
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
        context.showOfItem[turns[(turn + turns.count) % turns.count]]
    }

    private func candidate(at turn: Int, in context: ScheduleContext) -> Int {
        let item = turns[turn]
        guard followsEpisodes else { return item }
        let show = context.showOfItem[item]
        return context.shows[show][episode[show]]
    }

    private mutating func takeDueTurn(_ item: Int, in context: ScheduleContext) -> Int {
        position = (position + 1) % turns.count
        return take(item, in: context)
    }

    private mutating func take(_ item: Int, in context: ScheduleContext) -> Int {
        let show = context.showOfItem[item]
        if followsEpisodes {
            episode[show] = (episode[show] + 1) % context.shows[show].count
        }
        lastShow = show
        return item
    }
}
