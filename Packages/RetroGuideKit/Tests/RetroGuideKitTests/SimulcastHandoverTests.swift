import Foundation
import Testing
@testable import RetroGuideKit

/// The coordinator simulates each period on its own; these check that the
/// joins can't be seen and that the rules hold across them.
@Suite("Simulcast periods")
struct SimulcastHandoverTests {
    /// Channels that all share every show, some rotating and some cycling,
    /// one exempt from the limit: plenty of clashes to step around.
    private static func coordinator(grid: ScheduleGrid = .continuous) -> (SimulcastCoordinator, [any ChannelSchedule]) {
        var deep: [MediaItem] = []
        for show in 0..<24 {
            deep += (1...60).map { TestFactory.episode("d\(show)-\($0)", show: "Deep\(show)", number: $0, duration: TimeInterval(22 + show % 3 * 22) * 60 + 7.5) }
        }
        let shallow = Array(deep.filter { ["Deep0", "Deep1", "Deep2", "Deep3"].contains($0.series?.title) })
        let channels: [(ScheduleContext, ScheduleOrdering)] = [
            (ScheduleContext(channelID: "a", items: deep, grid: grid), .syndication),
            (ScheduleContext(channelID: "b", items: deep, grid: grid), .blockShuffle),
            (ScheduleContext(channelID: "c", items: deep, grid: grid), .shuffle),
            (ScheduleContext(channelID: "d", items: shallow, grid: grid), .syndication),
            (ScheduleContext(channelID: "e", items: shallow, grid: grid), .marathon),
            (ScheduleContext(channelID: "f", items: deep, grid: grid), .syndication),
        ]
        let coordinator = SimulcastCoordinator(limit: 2, channels: channels, uncounted: [5])
        return (coordinator, channels.indices.map { coordinator.timeline(for: $0) })
    }

    @Test("Each period's run agrees with the previous one where they meet", arguments: [ScheduleGrid.continuous, .halfHour])
    func seamless(grid: ScheduleGrid) {
        let (coordinator, _) = Self.coordinator(grid: grid)
        for period in 20...26 {
            let (seamless, of) = coordinator.seamlessChannels(at: period)
            #expect(seamless == of, "period \(period): \(seamless) of \(of)")
        }
    }

    @Test("Programs join up exactly and stay in order across a period start")
    func contiguous() throws {
        let (_, timelines) = Self.coordinator()
        let start = ScheduleTime.date(SimulcastCoordinator.periodStart(30))
        for timeline in timelines {
            let programs = timeline.programs(overlapping: DateInterval(start: start.addingTimeInterval(-86_400), duration: 2 * 86_400))
            var next: [String: Int] = [:]
            for (first, second) in zip(programs, programs.dropFirst()) {
                #expect(first.slotEnd == second.start)
                #expect(timeline.program(at: second.start) == second)
            }
            for program in programs {
                guard let show = program.item.series?.title, let number = program.item.series?.episodeNumber else { continue }
                if let expected = next[show] {
                    #expect(number == expected || number == 1, "\(timeline.channelID) \(show) jumped to \(number)")
                }
                next[show] = number + 1
            }
        }
    }

    @Test("Rules hold across a period start")
    func rules() {
        let (_, timelines) = Self.coordinator()
        let start = ScheduleTime.date(SimulcastCoordinator.periodStart(30))
        for minute in stride(from: -1_440, to: 1_440, by: 7) {
            let date = start.addingTimeInterval(TimeInterval(minute) * 60 + 1)
            let airing = timelines.compactMap { $0.program(at: date) }
            #expect(Set(airing.map(\.item.id)).count == airing.count, "same episode at \(minute)")
            let counted = airing.filter { $0.channelID != "f" }
            #expect(!Dictionary(grouping: counted, by: \.item.showID).values.contains { $0.count > 2 }, "over the limit at \(minute)")
        }
    }

    @Test("Any moment, however far off, comes out the same however it's reached")
    func farOff() throws {
        let date = ScheduleConstants.epoch.addingTimeInterval(60 * 365 * 86_400)
        let (_, direct) = Self.coordinator()
        let (_, walked) = Self.coordinator()
        var program = try #require(walked[1].program(at: date.addingTimeInterval(-3 * 86_400)))
        while program.slotEnd <= date {
            program = try #require(walked[1].program(after: program))
        }
        #expect(direct[1].program(at: date) == program)
    }
}
