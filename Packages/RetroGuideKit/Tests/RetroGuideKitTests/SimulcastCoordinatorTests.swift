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
