import Foundation
import Testing
@testable import RetroTVKit

@Suite("ChannelTimeline")
struct ChannelTimelineTests {
    private let items = TestFactory.show("Alpha", episodes: 12) + TestFactory.show("Beta", episodes: 7)
    private let sampleDate = Date(timeIntervalSince1970: 1_790_000_000)

    @Test("The program at a date always contains that date")
    func programContainsDate() throws {
        let timeline = TestFactory.timeline(items)
        for offset in stride(from: 0.0, to: 86_400, by: 997) {
            let date = sampleDate.addingTimeInterval(offset)
            let program = try #require(timeline.program(at: date))
            #expect(program.contains(date))
        }
    }

    @Test("Consecutive programs are back to back across cycle boundaries")
    func programsAreContiguous() throws {
        let timeline = TestFactory.timeline(items)
        var program = try #require(timeline.program(at: sampleDate))
        for _ in 0..<(items.count * 3) {
            let next = try #require(timeline.program(after: program))
            #expect(abs(next.start.timeIntervalSince(program.slotEnd)) < 0.001)
            program = next
        }
    }

    @Test("Schedules are identical across instances (stable across launches)")
    func deterministic() {
        let first = TestFactory.timeline(items, ordering: .blockShuffle)
        let second = TestFactory.timeline(items, ordering: .blockShuffle)
        let window = DateInterval(start: sampleDate, duration: 3 * 86_400)
        #expect(first.programs(overlapping: window).map(\.id) == second.programs(overlapping: window).map(\.id))
        #expect(first.programs(overlapping: window).map(\.item.id) == second.programs(overlapping: window).map(\.item.id))
    }

    @Test("Every cycle airs every item exactly once")
    func cycleIsPermutation() throws {
        let timeline = TestFactory.timeline(items)
        let first = try #require(timeline.program(at: sampleDate))
        var program = first
        var aired: [String] = []
        // Walk to the start of the next cycle, then collect one full cycle.
        while program.cycle == first.cycle {
            program = try #require(timeline.program(after: program))
        }
        let cycle = program.cycle
        while program.cycle == cycle {
            aired.append(program.item.id)
            program = try #require(timeline.program(after: program))
        }
        #expect(aired.sorted() == items.map(\.id).sorted())
    }

    @Test("Grid alignment rounds slots up and leaves an intermission")
    func gridAlignment() throws {
        let timeline = TestFactory.timeline(items, grid: .halfHour)
        let program = try #require(timeline.program(at: sampleDate))
        #expect(program.slotEnd.timeIntervalSince(program.start) == TestFactory.halfHour)
        #expect(program.isInIntermission(at: program.contentEnd))
    }

    @Test("An empty channel has no programs")
    func emptyTimeline() {
        let timeline = TestFactory.timeline([])
        #expect(timeline.isEmpty)
        #expect(timeline.program(at: sampleDate) == nil)
    }
}
