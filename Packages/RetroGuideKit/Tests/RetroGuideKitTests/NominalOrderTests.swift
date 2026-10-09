import Foundation
import Testing
@testable import RetroGuideKit

/// Channel orders as arithmetic: the same answers a program-by-program walk
/// gives, without the walk.
@Suite("Nominal orders")
struct NominalOrderTests {
    /// A channel of `shows` shows with mixed episode counts and lengths.
    static func context(shows: Int, grid: ScheduleGrid = .continuous) -> ScheduleContext {
        var items: [MediaItem] = []
        for show in 0..<shows {
            let episodes = 3 + (show * 17) % 60
            let length = TimeInterval([22, 24, 44, 48, 60][show % 5]) * 60
            for number in 1...episodes {
                items.append(TestFactory.episode("s\(show)e\(number)", show: "Show\(show)", season: 1 + number / 25, number: number, duration: length + TimeInterval(number % 7) * 10.123))
            }
        }
        return ScheduleContext(channelID: "channel.\(shows)", items: items, grid: grid)
    }

    @Test("A show reel's airtime adds up airing by airing, across passes")
    func reel() {
        let context = Self.context(shows: 1)
        let reel = ShowReel(items: context.shows[0], slotLengths: context.slotLengths, start: 2)
        var total = 0
        for airing in 0..<(reel.count * 3 + 1) {
            #expect(reel.airtime(airing) == total)
            total += context.slotLengths[reel.item(ofAiring: airing)]
        }
    }

    @Test("Orders are contiguous, invertible and keep every show's episodes in order", arguments: [ScheduleOrdering.shuffle, .syndication, .blockShuffle, .marathon], [false, true])
    func orders(ordering: ScheduleOrdering, rotates: Bool) {
        let context = Self.context(shows: rotates ? 24 : 5, grid: .halfHour)
        let order = NominalOrders.make(ordering: ordering, context: context)
        var nextAiring: [Int: Int] = [:]
        var start = order.start(of: 0)
        for position in 0..<3_000 {
            let (show, item) = order.program(at: position)
            #expect(order.start(of: position) == start)
            #expect(order.position(at: start) == position)
            #expect(order.position(at: start + context.slotLengths[item] - 1) == position)
            let episodes = context.shows[show]
            let index = episodes.firstIndex(of: item)!
            if let expected = nextAiring[show] {
                #expect(index == expected)
            }
            nextAiring[show] = (index + 1) % episodes.count
            start += context.slotLengths[item]
        }
    }

    @Test("Show rotation gives every show one turn per cycle, in a fixed order")
    func cycleTurns() {
        let context = Self.context(shows: 5)
        let order = CycleOrder(ordering: .syndication, context: context)
        let first = (0..<5).map { order.program(at: $0).show }
        #expect(Set(first).count == 5)
        #expect((5..<10).map { order.program(at: $0).show } == first)
    }

    @Test("Finding a far-off moment takes no replay and agrees with walking there")
    func farOff() {
        let context = Self.context(shows: 24)
        let order = NominalOrders.make(ordering: .syndication, context: context)
        let offset = 50 * 365 * ScheduleTime.perDay
        let position = order.position(at: offset)
        #expect(order.start(of: position) <= offset)
        #expect(order.start(of: position + 1) > offset)
        #expect(order.start(of: position + 1) - order.start(of: position) == context.slotLengths[order.program(at: position).item])
    }

    @Test("A channel on its own is contiguous and finds any moment")
    func standalone() throws {
        let context = Self.context(shows: 24)
        let timeline = NominalTimeline(context: context, ordering: .blockShuffle)
        let date = ScheduleConstants.epoch.addingTimeInterval(4_000 * 86_400)
        var program = try #require(timeline.program(at: date))
        #expect(program.contains(date))
        for _ in 0..<200 {
            let next = try #require(timeline.program(after: program))
            #expect(next.start == program.slotEnd)
            #expect(timeline.program(at: next.start) == next)
            program = next
        }
    }
}
