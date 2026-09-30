import Foundation
import Testing
@testable import RetroGuideKit

@Suite("Simulcast coordinator")
struct SimulcastCoordinatorTests {
    private static let week = DateInterval(start: ScheduleConstants.epoch.addingTimeInterval(30 * 86_400), duration: 7 * 86_400)

    private static func coordinated(
        _ channels: [(id: String, items: [MediaItem], ordering: ScheduleOrdering)],
        limit: Int
    ) -> [any ChannelSchedule] {
        let coordinator = SimulcastCoordinator(limit: limit, channels: channels.map {
            (ScheduleContext(channelID: $0.id, items: $0.items, grid: .continuous), $0.ordering)
        })
        return channels.indices.map { coordinator.timeline(for: $0) }
    }

    /// Most channels airing one show at any moment in `interval`.
    private static func mostAtOnce(_ timelines: [any ChannelSchedule], in interval: DateInterval) -> Int {
        var events: [(Date, Int, String)] = []
        for timeline in timelines {
            for program in timeline.programs(overlapping: interval) {
                let show = program.item.seriesID ?? program.item.id
                events.append((program.start, 1, show))
                events.append((program.slotEnd, -1, show))
            }
        }
        events.sort { ($0.0, $0.1) < ($1.0, $1.1) }
        var airing: [String: Int] = [:]
        var most = 0
        for (_, change, show) in events {
            airing[show, default: 0] += change
            most = max(most, airing[show, default: 0])
        }
        return most
    }

    private static func sharedShows(_ count: Int) -> [MediaItem] {
        (1...count).flatMap { TestFactory.show("Show\($0)", episodes: 20) }
    }

    @Test("No show airs on more channels at once than the limit", arguments: [1, 2], [ScheduleOrdering.syndication, .shuffle, .blockShuffle])
    func limitHolds(limit: Int, ordering: ScheduleOrdering) {
        let items = Self.sharedShows(8)
        let timelines = Self.coordinated((1...4).map { ("channel.\($0)", items, ordering) }, limit: limit)
        #expect(Self.mostAtOnce(timelines, in: Self.week) <= limit)
    }

    /// Longest time one episode is on two of the timelines at once.
    private static func sameEpisodeOverlap(_ timelines: [any ChannelSchedule], in interval: DateInterval) -> TimeInterval {
        let programs = timelines.flatMap { $0.programs(overlapping: interval) }
        var longest: TimeInterval = .zero
        for (_, airings) in Dictionary(grouping: programs, by: \.item.id) {
            for (index, first) in airings.enumerated() {
                for second in airings.dropFirst(index + 1) where first.channelID != second.channelID {
                    let shared = min(first.slotEnd, second.slotEnd).timeIntervalSince(max(first.start, second.start))
                    longest = max(longest, shared)
                }
            }
        }
        return longest
    }

    @Test("No episode is on two channels at once, however many may air its show", arguments: [1, 2, Int.max])
    func noSameEpisode(limit: Int) {
        // Short shows on as many channels as there are shows: channels that
        // started in step would keep clashing.
        let items = (1...4).flatMap { TestFactory.show("Show\($0)", episodes: 4) }
        let timelines = Self.coordinated((1...4).map { ("channel.\($0)", items, .syndication) }, limit: limit)
        #expect(Self.sameEpisodeOverlap(timelines, in: Self.week) <= .zero)
    }

    @Test("Channels steer clear of what a 24/7 channel is airing")
    func avoidsFixedChannels() {
        let marathon = TestFactory.show("Show1", episodes: 6)
        let fixed = ChannelTimeline(channelID: "marathon", items: marathon, ordering: .syndication, grid: .continuous)
        let items = Self.sharedShows(3)
        let coordinator = SimulcastCoordinator(
            limit: 2,
            channels: (1...3).map { (ScheduleContext(channelID: "channel.\($0)", items: items, grid: .continuous), .syndication) },
            fixed: fixed.repeatingSlots()
        )
        let timelines: [any ChannelSchedule] = (0..<3).map { coordinator.timeline(for: $0) } + [fixed]
        #expect(Self.sameEpisodeOverlap(timelines, in: Self.week) <= .zero)
    }

    @Test("Uncounted channels don't use up the limit")
    func uncountedChannels() {
        let items = Self.sharedShows(1)
        let coordinator = SimulcastCoordinator(
            limit: 1,
            channels: (1...2).map { (ScheduleContext(channelID: "channel.\($0)", items: items, grid: .continuous), .syndication) },
            uncounted: [0]
        )
        let timelines = (0..<2).map { coordinator.timeline(for: $0) }
        #expect(Self.mostAtOnce(timelines, in: Self.week) == 2)
        #expect(Self.sameEpisodeOverlap(timelines, in: Self.week) <= .zero)
    }

    @Test("Without clashes to avoid, channels keep their full mix")
    func keepsVariety() throws {
        let items = Self.sharedShows(8)
        let timelines = Self.coordinated((1...3).map { ("channel.\($0)", items, .syndication) }, limit: 1)
        for timeline in timelines {
            let day = timeline.programs(overlapping: DateInterval(start: Self.week.start, duration: 86_400))
            #expect(Set(day.map { $0.item.seriesID }).count >= 6)
        }
    }

    @Test("A show keeps its episode order when it has to wait its turn")
    func episodesStayInOrder() throws {
        let items = Self.sharedShows(4)
        let timelines = Self.coordinated((1...3).map { ("channel.\($0)", items, .syndication) }, limit: 1)
        for timeline in timelines {
            var last: [String: Int] = [:]
            for program in timeline.programs(overlapping: Self.week) {
                guard let show = program.item.seriesID, let number = program.item.series?.episodeNumber else { continue }
                if let previous = last[show], number != previous + 1 {
                    #expect(number == 1, "\(show) jumped from \(previous) to \(number)")
                }
                last[show] = number
            }
        }
    }

    @Test("Schedules are the same however they're queried")
    func deterministic() throws {
        let items = Self.sharedShows(6)
        let channels: [(id: String, items: [MediaItem], ordering: ScheduleOrdering)] = (1...3).map { ("channel.\($0)", items, .shuffle) }
        let date = Self.week.end
        let direct = Self.coordinated(channels, limit: 1)[2].program(at: date)
        let warmed = Self.coordinated(channels, limit: 1)
        _ = warmed[0].programs(overlapping: Self.week)
        #expect(warmed[2].program(at: date) == direct)
    }

    @Test("Programs are contiguous across simulated days")
    func contiguous() throws {
        let timeline = Self.coordinated([("channel.1", Self.sharedShows(3), .syndication)], limit: 1)[0]
        let programs = timeline.programs(overlapping: Self.week)
        for (first, second) in zip(programs, programs.dropFirst()) {
            #expect(first.slotEnd == second.start)
        }
    }

    @Test("A channel with nothing playable is empty, not a crash")
    func emptyChannel() {
        let timelines = Self.coordinated([("channel.1", [], .marathon), ("channel.2", Self.sharedShows(2), .syndication)], limit: 1)
        #expect(timelines[0].isEmpty)
        #expect(timelines[0].program(at: Self.week.start) == nil)
        #expect(timelines[1].program(at: Self.week.start) != nil)
    }
}
