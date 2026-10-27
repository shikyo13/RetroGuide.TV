import Foundation
import Testing
@testable import RetroGuideKit

/// New library content joins at the next broadcast-day boundary and never
/// changes anything scheduled before it; shows carry on in order across it.
@Suite("Stable schedules")
struct StableScheduleTests {
    /// About 1,000 days after the epoch, at 03:00 UTC: joins at 09:00 that day.
    private static let added = ScheduleConstants.epoch.addingTimeInterval(1_000 * 86_400 + 3 * 3_600)
    private static let boundary = ContentVersions.effectiveTime(addedAt: added)

    private static func show(_ name: String, episodes: Int, minutes: Int, addedAt: Date? = nil) -> [MediaItem] {
        (1...episodes).map {
            TestFactory.episode("\(name)-\($0)", show: name, season: 1 + $0 / 20, number: $0, duration: TimeInterval(minutes * 60) + TimeInterval($0 % 5) * 7.5, addedAt: addedAt)
        }
    }

    /// A small channel (cycles) or a deep one (rotates in lanes).
    private static func library(deep: Bool) -> [MediaItem] {
        let count = deep ? 14 : 4
        return (0..<count).flatMap { show("Show\($0)", episodes: deep ? 40 + $0 * 3 : 12 + $0, minutes: [22, 44, 30][$0 % 3]) }
    }

    /// The library plus one new episode of an existing show and one new show, added at ``added``.
    private static func withAdditions(_ base: [MediaItem]) -> [MediaItem] {
        let next = TestFactory.episode("Show1-new", show: "Show1", season: 9, number: 1, duration: 1_500, addedAt: added)
        return base + [next] + show("Newcomer", episodes: 10, minutes: 25, addedAt: added)
    }

    private static let cases: [(ScheduleOrdering, Bool)] = [
        (.syndication, false), (.shuffle, false), (.blockShuffle, false), (.marathon, false),
        (.syndication, true), (.blockShuffle, true), (.marathon, true),
    ]

    @Test("New content joins at the next 09:00 UTC at least an hour after it was added")
    func effectiveTimes() {
        let day = 1_000 * ScheduleTime.perDay
        let nine = 9 * 3_600_000
        func at(_ hours: Double) -> Date { ScheduleConstants.epoch.addingTimeInterval(1_000 * 86_400 + hours * 3_600) }
        #expect(ContentVersions.effectiveTime(addedAt: at(3)) == day + nine)
        #expect(ContentVersions.effectiveTime(addedAt: at(8.5)) == day + ScheduleTime.perDay + nine)
        #expect(ContentVersions.effectiveTime(addedAt: nil) == 0)
        #expect(ContentVersions.effectiveTime(addedAt: Date(timeIntervalSince1970: 0)) == 0)
    }

    @Test("Before the boundary, the order is exactly what it was without the new content", arguments: cases)
    func unchangedBefore(ordering: ScheduleOrdering, deep: Bool) {
        let base = Self.library(deep: deep)
        let before = NominalOrders.make(ordering: ordering, context: ScheduleContext(channelID: "c", items: base, grid: .continuous))
        let afterContext = ScheduleContext(channelID: "c", items: Self.withAdditions(base), grid: .continuous)
        let after = NominalOrders.make(ordering: ordering, context: afterContext)
        let baseItems = base.map(\.id)
        var position = before.position(at: Self.boundary - 3 * ScheduleTime.perDay)
        while before.start(of: position + 1) <= Self.boundary {
            #expect(before.start(of: position) == after.start(of: position))
            #expect(baseItems[before.program(at: position).item] == afterContext.items[after.program(at: position).item].id)
            position += 1
        }
    }

    @Test("Across the boundary every show carries on with its next episode, and the new content airs", arguments: cases)
    func continuesAfter(ordering: ScheduleOrdering, deep: Bool) {
        let context = ScheduleContext(channelID: "c", items: Self.withAdditions(Self.library(deep: deep)), grid: .continuous)
        let order = NominalOrders.make(ordering: ordering, context: context)
        var next: [Int: Int] = [:]
        var sawNewcomer = false
        var position = order.position(at: Self.boundary - 2 * ScheduleTime.perDay)
        var time = order.start(of: position)
        for _ in 0..<6_000 {
            let (show, item) = order.program(at: position)
            #expect(order.start(of: position) == time)
            #expect(order.position(at: time) == position)
            // The show's episodes as of this moment, in broadcast order.
            let episodes = context.shows[show].filter { context.effective[$0] <= time }
            let index = episodes.firstIndex(of: item)!
            if let expected = next[show] {
                #expect(episodes[expected % episodes.count] == item, "\(context.showIDs[show]) skipped or repeated at \(time - Self.boundary) ms")
            }
            next[show] = index + 1
            if context.items[item].headline == "Newcomer" {
                sawNewcomer = true
                #expect(time >= Self.boundary)
            }
            time += context.slotLengths[item]
            position += 1
        }
        #expect(sawNewcomer)
    }

    @Test("A new show slots into the turn order without moving the other shows")
    func othersKeepTheirOrder() {
        let base = Self.library(deep: false)
        let before = NominalOrders.make(ordering: .syndication, context: ScheduleContext(channelID: "c", items: base, grid: .continuous))
        let afterContext = ScheduleContext(channelID: "c", items: base + Self.show("Newcomer", episodes: 10, minutes: 25, addedAt: Self.added), grid: .continuous)
        let after = NominalOrders.make(ordering: .syndication, context: afterContext)
        var position = after.position(at: Self.boundary)
        if after.start(of: position) < Self.boundary { position += 1 }
        var old: [String] = []
        var new: [String] = []
        for offset in 0..<200 {
            old.append(base[before.program(at: position + offset).item].id)
            let item = afterContext.items[after.program(at: position + offset).item]
            if item.headline != "Newcomer" { new.append(item.id) }
        }
        #expect(Array(old.prefix(new.count)) == new)
    }

    @Test("With channels sharing shows, nothing before the boundary changes on any channel")
    func coordinatedBefore() throws {
        let base = Self.library(deep: true)
        func timelines(_ items: [MediaItem]) -> [any ChannelSchedule] {
            let channels: [(ScheduleContext, ScheduleOrdering)] = [
                (ScheduleContext(channelID: "a", items: items, grid: .continuous), .syndication),
                (ScheduleContext(channelID: "b", items: items, grid: .continuous), .blockShuffle),
                (ScheduleContext(channelID: "c", items: Array(items.prefix(60)), grid: .continuous), .shuffle),
                (ScheduleContext(channelID: "d", items: items, grid: .continuous), .syndication),
            ]
            let coordinator = SimulcastCoordinator(limit: 2, channels: channels, uncounted: [3])
            return channels.indices.map { coordinator.timeline(for: $0) }
        }
        let before = timelines(base)
        let after = timelines(Self.withAdditions(base))
        let boundary = ScheduleTime.date(Self.boundary)
        let window = DateInterval(start: boundary.addingTimeInterval(-3 * 86_400), end: boundary)
        for (old, new) in zip(before, after) {
            let oldPrograms = old.programs(overlapping: window).filter { $0.start < boundary }
            let newPrograms = new.programs(overlapping: window).filter { $0.start < boundary }
            #expect(oldPrograms.map(\.item.id) == newPrograms.map(\.item.id), "\(old.channelID)")
            #expect(oldPrograms.map(\.start) == newPrograms.map(\.start), "\(old.channelID)")
        }
    }
}

@Suite("Stable schedules: bad dates")
struct StableScheduleBadDateTests {
    @Test("Added dates far in the future count as always there")
    func futureDates() {
        let now = Date(timeIntervalSince1970: 1_791_000_000)
        #expect(ContentVersions.effectiveTime(addedAt: Date(timeIntervalSince1970: 5_557_000_000), now: now) == 0)
        #expect(ContentVersions.effectiveTime(addedAt: now.addingTimeInterval(3_600), now: now) > 0)
    }
}
