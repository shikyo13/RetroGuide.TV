import Foundation
import Testing
@testable import RetroGuideKit

@Suite("Bounded schedule history")
struct CompositeOrderMemoryTests {
    @Test("Evicting history preserves programs and times across forward and backward queries", arguments: [ScheduleOrdering.shuffle, .syndication, .blockShuffle, .marathon])
    func replay(ordering: ScheduleOrdering) {
        let items = (0..<96).flatMap { day in
            (0..<3).map { episode in
                TestFactory.episode("d\(day)e\(episode)", show: "Show\(day % 12)", season: 1, number: day * 3 + episode, duration: 1320,
                    addedAt: ScheduleConstants.epoch.addingTimeInterval(Double(day * 86400)))
            }
        }
        let context = ScheduleContext(channelID: "history", items: items, grid: .continuous)
        let bounded = CompositeOrder.build(ordering: ordering, context: context, budget: nil)
        let reference = RetainedHistoryOrder.build(ordering: ordering, context: context, budget: nil)
        let days = Array(0..<100) + Array((0..<100).reversed()) + [2, 95, 8, 87, 1, 99]
        for day in days {
            let time = day * ScheduleTime.perDay + ScheduleTime.perDay / 2
            let position = reference.position(at: time)
            #expect(bounded.position(at: time) == position)
            for offset in 0..<3 {
                #expect(bounded.start(of: position + offset) == reference.start(of: position + offset))
                #expect(bounded.program(at: position + offset).item == reference.program(at: position + offset).item)
            }
            #expect(bounded.retainedSegmentCount <= CompositeOrder.Tuning.cachedSegments)
        }
    }
}

/// The eager reference retains all historical orders so eviction can be
/// tested against the original schedule independently of its cache.
struct RetainedHistoryOrder: NominalOrder {
    private let positions: [Int]
    private let times: [Int]
    private let segments: [any OrderSegment]

    static func build(ordering: ScheduleOrdering, context: ScheduleContext, budget: BudgetSchedule?) -> RetainedHistoryOrder {
        var shelf = EpisodeShelf(context: context)
        let budgetTimes = budget?.changeTimes ?? []
        let versions = Set(context.versionTimes + budgetTimes).sorted()
        var positions: [Int] = []
        var times: [Int] = []
        var segments: [any OrderSegment] = []
        for time in versions {
            shelf.advance(to: time)
            guard !shelf.shows.isEmpty else { continue }
            let keep = budget?.keep(at: time)
            guard let last = segments.last, let lastPosition = positions.last, let lastTime = times.last else {
                positions.append(.zero)
                times.append(time)
                segments.append(segment(ordering: ordering, context: context, shelf: shelf, keep: keep, from: nil, reusing: nil))
                continue
            }
            // The first program of the old version starting at or after the
            // change hands over to the new one, at its own start time.
            var local = last.position(at: time - lastTime)
            if last.start(of: local) < time - lastTime {
                local += 1
            }
            let state = last.state(at: local)
            positions.append(lastPosition + local)
            times.append(lastTime + last.start(of: local))
            segments.append(segment(ordering: ordering, context: context, shelf: shelf, keep: keep, from: state, reusing: (last as? CycleSegment)?.template))
        }
        return RetainedHistoryOrder(positions: positions, times: times, segments: segments)
    }

    private static func segment(ordering: ScheduleOrdering, context: ScheduleContext, shelf: EpisodeShelf, keep: [Int]?, from state: SpliceState?, reusing template: CycleSegment.Template?) -> any OrderSegment {
        guard NominalOrders.rotates(ordering: ordering, titles: shelf.shows.count, content: shelf.content) else {
            return CycleSegment(ordering: ordering, context: context, shelf: shelf, keep: keep, from: state, reusing: template)
        }
        return LaneSegment(ordering: ordering, context: context, shelf: shelf, from: state)
    }

    func start(of position: Int) -> Int {
        guard !segments.isEmpty else { return .zero }
        let index = segment(containingPosition: position)
        return times[index] + segments[index].start(of: position - positions[index])
    }

    func program(at position: Int) -> (show: Int, item: Int) {
        let index = segment(containingPosition: position)
        return segments[index].program(at: position - positions[index])
    }

    func position(at offset: Int) -> Int {
        guard !segments.isEmpty, offset >= times[0] else { return .zero }
        let index = NominalOrders.lastNotAfter(offset, upper: times.count - 1) { times[$0] }
        return positions[index] + segments[index].position(at: offset - times[index])
    }

    private func segment(containingPosition position: Int) -> Int {
        NominalOrders.lastNotAfter(position, upper: positions.count - 1) { positions[$0] }
    }
}
