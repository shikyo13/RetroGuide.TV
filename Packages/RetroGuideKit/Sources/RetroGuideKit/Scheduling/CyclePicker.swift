import Foundation

/// Airs a channel's items in one fixed order, cycle after cycle, so nothing
/// repeats until everything has aired.
///
/// A turn whose show may not air now (it's on enough other channels) is
/// missed and made up as soon as the show is free, before the channel moves
/// on. The order itself never changes, so shows stay spread out however many
/// turns get made up. Shows keep their place in their episode order, so a
/// delayed show resumes with the episode it missed instead of jumping ahead.
struct CyclePicker: ProgramPicker {
    enum Tuning {
        /// Turns to look ahead for one that may air before giving up.
        static let lookahead = 256
        /// Missed turns remembered for making up; past this the oldest is dropped.
        static let maximumMissed = 32
    }

    /// Item indices in airing order.
    private let turns: [Int]
    /// Whether turns stand for "the show's next episode" (episodic orderings)
    /// rather than a specific item (shuffle).
    private let followsEpisodes: Bool
    private var position = 0
    /// Turns (positions in ``turns``) missed while their show was blocked, oldest first.
    private var missed: [Int] = []
    /// Next episode of every show, when following episodes.
    private var episode: [Int]

    init(ordering: ScheduleOrdering, context: ScheduleContext) {
        var generator = SeededGenerator(seed: context.seed)
        let playable = context.shows.flatMap { $0 }.sorted()
        let order = PlaylistArranger.arrange(playable.map { context.items[$0] }, ordering: ordering, using: &generator)
        turns = order.map { playable[$0] }
        followsEpisodes = ordering != .shuffle
        episode = Array(repeating: 0, count: context.shows.count)
    }

    mutating func next(at offset: TimeInterval, in context: ScheduleContext, isAllowed: (Int) -> Bool) -> Int {
        if let index = missed.firstIndex(where: { isAllowed(candidate(at: $0, in: context)) }) {
            return take(candidate(at: missed.remove(at: index), in: context), in: context)
        }
        let startPosition = position
        let startMissed = missed
        for _ in 0..<min(turns.count, Tuning.lookahead) {
            let turn = advance()
            let item = candidate(at: turn, in: context)
            if isAllowed(item) {
                return take(item, in: context)
            }
            miss(turn)
        }
        // Nothing may air: better a simulcast than dead air.
        position = startPosition
        missed = startMissed
        return take(candidate(at: advance(), in: context), in: context)
    }

    private mutating func advance() -> Int {
        let turn = position
        position = (position + 1) % turns.count
        return turn
    }

    private mutating func miss(_ turn: Int) {
        missed.append(turn)
        if missed.count > Tuning.maximumMissed {
            missed.removeFirst()
        }
    }

    private func candidate(at turn: Int, in context: ScheduleContext) -> Int {
        let item = turns[turn]
        guard followsEpisodes else { return item }
        let show = context.showOfItem[item]
        return context.shows[show][episode[show]]
    }

    private mutating func take(_ item: Int, in context: ScheduleContext) -> Int {
        if followsEpisodes {
            let show = context.showOfItem[item]
            episode[show] = (episode[show] + 1) % context.shows[show].count
        }
        return item
    }
}
