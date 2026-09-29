import Foundation

/// Airs a channel's items in one fixed order, cycle after cycle, so nothing
/// repeats until everything has aired.
///
/// When the show whose turn it is may not air now (it's on enough other
/// channels), its turn waits and the next show that may air goes early; the
/// turn it took is skipped when the order reaches it. Once the waiting show
/// is free again it alternates with the others rather than airing its backlog
/// back to back. The order itself never changes, and shows keep their place
/// in their episode order, so a delayed show resumes with the episode it
/// missed.
struct CyclePicker: ProgramPicker {
    enum Tuning {
        /// A shuffle item may rerun early (rather than a show going over the
        /// simulcast limit) only once it's been off this long.
        static let minimumRerunGap: TimeInterval = 24 * ScheduleConstants.secondsPerHour
    }

    /// Item indices in airing order.
    private let turns: [Int]
    /// Whether turns stand for "the show's next episode" (episodic orderings)
    /// rather than a specific item (shuffle).
    private let followsEpisodes: Bool
    /// The turn due next.
    private var position = 0
    /// Turns that already aired early, and how many times (a show waiting a
    /// long time lets the others run ahead by more than one cycle).
    private var airedEarly: [Int32]
    private var lastShow: Int?
    /// Next episode of every show, when following episodes.
    private var episode: [Int]
    /// When each item last aired (shuffle only), for picking an early rerun.
    private var lastAired: [TimeInterval]

    init(ordering: ScheduleOrdering, context: ScheduleContext) {
        var generator = SeededGenerator(seed: context.seed)
        let playable = context.shows.flatMap { $0 }.sorted()
        let order = PlaylistArranger.arrange(playable.map { context.items[$0] }, ordering: ordering, using: &generator)
        turns = order.map { playable[$0] }
        followsEpisodes = ordering != .shuffle
        episode = Array(repeating: 0, count: context.shows.count)
        lastAired = followsEpisodes ? [] : Array(repeating: -.infinity, count: context.items.count)
        airedEarly = Array(repeating: 0, count: turns.count)
    }

    mutating func next(at offset: TimeInterval, in context: ScheduleContext, isAllowed: (Int) -> Bool) -> Int {
        skipTurnsAiredEarly()
        let due = candidate(at: position, in: context)
        let dueShow = context.showOfItem[due]
        // Back to back only where the order means it (a block of episodes).
        let isRepeat = dueShow == lastShow && show(ofTurn: position - 1, in: context) != dueShow
        if !isRepeat, isAllowed(due) {
            return takeDueTurn(due, at: offset, in: context)
        }
        let avoided = isRepeat ? dueShow : nil
        // Taking a turn that already aired early runs a show further ahead
        // of its share, so only as a last resort; for shuffle it airs that
        // item again, so it must be the one off the longest.
        let early = firstAllowedAhead(avoiding: avoided, reusing: false, in: context, isAllowed: isAllowed)
            ?? (followsEpisodes
                ? firstAllowedAhead(avoiding: avoided, reusing: true, in: context, isAllowed: isAllowed)
                : longestOffAllowed(at: offset, in: context, isAllowed: isAllowed))
        if let (turn, item) = early {
            airedEarly[turn] += 1
            return take(item, at: offset, in: context)
        }
        // Only the due show may air, or nothing may: better a simulcast than dead air.
        return takeDueTurn(due, at: offset, in: context)
    }

    /// The shuffle turn, of those that may air, whose item has been off the
    /// longest (and at least ``Tuning/minimumRerunGap``).
    private func longestOffAllowed(at offset: TimeInterval, in context: ScheduleContext, isAllowed: (Int) -> Bool) -> (turn: Int, item: Int)? {
        var best: (turn: Int, item: Int)?
        for turn in turns.indices {
            let item = turns[turn]
            guard offset - lastAired[item] >= Tuning.minimumRerunGap,
                  best.map({ lastAired[item] < lastAired[$0.item] }) ?? true,
                  isAllowed(item)
            else { continue }
            best = (turn, item)
        }
        return best
    }

    private mutating func skipTurnsAiredEarly() {
        while airedEarly[position] > 0 {
            airedEarly[position] -= 1
            position = (position + 1) % turns.count
        }
    }

    /// The nearest later turn (wrapping into the next cycle) whose show may air.
    private func firstAllowedAhead(
        avoiding avoided: Int?,
        reusing: Bool,
        in context: ScheduleContext,
        isAllowed: (Int) -> Bool
    ) -> (turn: Int, item: Int)? {
        // Usually a handful of shows: a list beats hashing.
        var blocked: [Int] = avoided.map { [$0] } ?? []
        for distance in 1..<turns.count {
            let turn = (position + distance) % turns.count
            guard reusing || airedEarly[turn] == 0 else { continue }
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

    private mutating func takeDueTurn(_ item: Int, at offset: TimeInterval, in context: ScheduleContext) -> Int {
        position = (position + 1) % turns.count
        return take(item, at: offset, in: context)
    }

    private mutating func take(_ item: Int, at offset: TimeInterval, in context: ScheduleContext) -> Int {
        let show = context.showOfItem[item]
        if followsEpisodes {
            episode[show] = (episode[show] + 1) % context.shows[show].count
        } else {
            lastAired[item] = offset
        }
        lastShow = show
        return item
    }
}
