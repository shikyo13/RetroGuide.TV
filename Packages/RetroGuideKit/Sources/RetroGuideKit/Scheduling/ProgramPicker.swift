import Foundation

/// Decides what airs next on a channel, one program at a time. Value types, so
/// a schedule can be checkpointed and continued.
protocol ProgramPicker: Sendable {
    /// The item (index into ``ScheduleContext/items``) to air starting at
    /// `offset` seconds after the epoch. `isAllowed` says whether an item may
    /// air now (``SimulcastCoordinator``); a picker passes over items that
    /// may not, and airs one anyway only when nothing else is left.
    mutating func next(at offset: TimeInterval, in context: ScheduleContext, isAllowed: (Int) -> Bool) -> Int
}

/// What a picker needs to know about a channel: its items grouped into shows
/// and how long each one's slot is.
final class ScheduleContext: Sendable {
    let channelID: String
    let items: [MediaItem]
    let slotLengths: [TimeInterval]
    /// Each show's (or movie's) item indices in broadcast order, specials last.
    let shows: [[Int]]
    /// Id of every show (series id, or the movie's own id).
    let showIDs: [String]
    /// Show index of every item.
    let showOfItem: [Int]
    let seed: UInt64

    init(channelID: String, items: [MediaItem], grid: ScheduleGrid) {
        self.channelID = channelID
        self.items = items
        self.slotLengths = items.map { max(grid.slotLength(for: $0.duration), ScheduleConstants.minimumProgramDuration) }
        var groups: [String: [Int]] = [:]
        for index in items.indices where items[index].duration > .zero {
            groups[items[index].seriesID ?? items[index].id, default: []].append(index)
        }
        let sorted = groups.sorted { $0.key < $1.key }
        self.showIDs = sorted.map(\.key)
        self.shows = sorted.map { _, indices in
            indices.sorted { lhs, rhs in
                let left = items[lhs].series?.broadcastOrder ?? (.zero, .zero)
                let right = items[rhs].series?.broadcastOrder ?? (.zero, .zero)
                return left != right ? left < right : items[lhs].id < items[rhs].id
            }
        }
        var showOfItem = Array(repeating: 0, count: items.count)
        for (show, indices) in shows.enumerated() {
            for index in indices {
                showOfItem[index] = show
            }
        }
        self.showOfItem = showOfItem
        self.seed = StableHash.fnv1a(channelID)
    }

    var isEmpty: Bool {
        shows.isEmpty
    }
}

/// The picker a channel runs: a rotating lineup when it has the depth for
/// one, otherwise one fixed order cycle after cycle.
enum ChannelPicker: ProgramPicker {
    case rotation(RotationPicker)
    case cycle(CyclePicker)
    /// Placeholder while the real picker is being mutated, so its arrays stay
    /// uniquely referenced and aren't copied on every program.
    case moving

    /// Channels with plenty of content run as a rotating lineup: shows take
    /// turns, continue where they left off and rest after finishing. Shuffle,
    /// and channels too small to keep shows rested, air everything once in a
    /// fixed order before anything repeats.
    init(ordering: ScheduleOrdering, context: ScheduleContext) {
        guard !context.isEmpty, Self.rotates(ordering: ordering, items: context.items) else {
            self = .cycle(CyclePicker(ordering: ordering, context: context))
            return
        }
        let plan: RotationPicker.Plan
        switch ordering {
        case .shuffle, .syndication: plan = .showRotation
        case .blockShuffle: plan = .blockShuffle
        case .marathon: plan = .marathon
        }
        self = .rotation(RotationPicker(plan: plan, context: context))
    }

    static func rotates(ordering: ScheduleOrdering, items: [MediaItem]) -> Bool {
        let titles = Set(items.map { $0.seriesID ?? $0.id }).count
        guard ordering != .shuffle, titles > 1 else { return false }
        guard ordering != .marathon else { return true }
        let content = items.reduce(TimeInterval.zero) { $0 + $1.duration }
        return content >= RotationPicker.Tuning.minimumContent && titles >= RotationPicker.Tuning.minimumShows
    }

    mutating func next(at offset: TimeInterval, in context: ScheduleContext, isAllowed: (Int) -> Bool) -> Int {
        switch self {
        case .rotation(var picker):
            self = .moving
            let item = picker.next(at: offset, in: context, isAllowed: isAllowed)
            self = .rotation(picker)
            return item
        case .cycle(var picker):
            self = .moving
            let item = picker.next(at: offset, in: context, isAllowed: isAllowed)
            self = .cycle(picker)
            return item
        case .moving:
            preconditionFailure("picker re-entered while moving")
        }
    }
}
