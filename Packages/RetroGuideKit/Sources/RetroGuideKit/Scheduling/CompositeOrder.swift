import Foundation

/// Carries a channel across content changes without retaining a full copy of
/// its running order for every day in the library's history. Historical
/// boundaries stay compact; evicted orders are reconstructed deterministically.
final class CompositeOrder: NominalOrder, @unchecked Sendable {
    enum Tuning {
        /// The active content version and its neighbor at a guide boundary.
        static let cachedSegments = 2
    }

    private let ordering: ScheduleOrdering
    private let context: ScheduleContext
    private let budget: BudgetSchedule?
    private var positions: [Int] = []
    private var times: [Int] = []
    private var versions: [Int] = []
    private let lock = NSLock()
    private var cache: [Int: any OrderSegment] = [:]
    private var recency: [Int] = []
    private var replay: Replay
    private var replayIndex = -1

    static func build(ordering: ScheduleOrdering, context: ScheduleContext, budget: BudgetSchedule?) -> CompositeOrder {
        CompositeOrder(ordering: ordering, context: context, budget: budget)
    }

    private init(ordering: ScheduleOrdering, context: ScheduleContext, budget: BudgetSchedule?) {
        self.ordering = ordering
        self.context = context
        self.budget = budget
        replay = Replay(context: context)
        for version in Set(context.versionTimes + (budget?.changeTimes ?? [])).sorted() {
            guard let entry = replay.advance(to: version, ordering: ordering, context: context, budget: budget) else { continue }
            positions.append(entry.position)
            times.append(entry.time)
            versions.append(version)
            replayIndex += 1
            remember(entry.segment, at: replayIndex)
        }
    }

    var retainedSegmentCount: Int {
        lock.withLock { cache.count }
    }

    func start(of position: Int) -> Int {
        lock.withLock {
            guard !times.isEmpty else { return .zero }
            let index = segment(containingPosition: position)
            return times[index] + order(at: index).start(of: position - positions[index])
        }
    }

    func program(at position: Int) -> (show: Int, item: Int) {
        lock.withLock {
            let index = segment(containingPosition: position)
            return order(at: index).program(at: position - positions[index])
        }
    }

    func position(at offset: Int) -> Int {
        lock.withLock {
            guard !times.isEmpty, offset >= times[0] else { return .zero }
            let index = NominalOrders.lastNotAfter(offset, upper: times.count - 1) { times[$0] }
            return positions[index] + order(at: index).position(at: offset - times[index])
        }
    }

    private func segment(containingPosition position: Int) -> Int {
        NominalOrders.lastNotAfter(position, upper: positions.count - 1) { positions[$0] }
    }

    private func order(at index: Int) -> any OrderSegment {
        if let segment = cache[index] {
            remember(segment, at: index)
            return segment
        }
        if index <= replayIndex {
            replay = Replay(context: context)
            replayIndex = -1
        }
        while replayIndex < index {
            replayIndex += 1
            if let entry = replay.advance(to: versions[replayIndex], ordering: ordering, context: context, budget: budget) {
                remember(entry.segment, at: replayIndex)
            }
        }
        return cache[index]!
    }

    private func remember(_ segment: any OrderSegment, at index: Int) {
        cache[index] = segment
        recency.removeAll { $0 == index }
        recency.append(index)
        while recency.count > Tuning.cachedSegments {
            cache[recency.removeFirst()] = nil
        }
    }

    /// Reconstruction advances through content changes, never individual
    /// airings. Sequential guide requests reuse the current reconstruction.
    private struct Replay {
        var shelf: EpisodeShelf
        var last: Entry?

        struct Entry {
            let position: Int
            let time: Int
            let segment: any OrderSegment
        }

        init(context: ScheduleContext) {
            shelf = EpisodeShelf(context: context)
        }

        mutating func advance(to time: Int, ordering: ScheduleOrdering, context: ScheduleContext, budget: BudgetSchedule?) -> Entry? {
            shelf.advance(to: time)
            guard !shelf.shows.isEmpty else { return nil }
            var position = 0
            var begins = time
            var state: SpliceState?
            if let last {
                var local = last.segment.position(at: time - last.time)
                if last.segment.start(of: local) < time - last.time { local += 1 }
                state = last.segment.state(at: local)
                position = last.position + local
                begins = last.time + last.segment.start(of: local)
            }
            let segment: any OrderSegment
            if NominalOrders.rotates(ordering: ordering, titles: shelf.shows.count, content: shelf.content) {
                segment = LaneSegment(ordering: ordering, context: context, shelf: shelf, from: state)
            } else {
                segment = CycleSegment(ordering: ordering, context: context, shelf: shelf, keep: budget?.keep(at: time), from: state, reusing: (last?.segment as? CycleSegment)?.template)
            }
            let entry = Entry(position: position, time: begins, segment: segment)
            last = entry
            return entry
        }
    }
}
