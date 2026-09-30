import Foundation
import Testing
@testable import RetroGuideKit

/// Scores generated lineups for libraries of every shape and size against the
/// goals of channel generation, so no change can quietly make small, huge or
/// oddly organized libraries worse.
@Suite("Lineup bench")
struct LineupBenchTests {
    enum Goal {
        /// Moments where some show is on more channels than allowed. Only
        /// libraries with enough titles for their channels can always avoid it.
        static let simulcastOverLimitShare = 0.0
        static let simulcastLibraryTitles = 150
        /// Below this, channels share so few titles that keeping episodes in
        /// order sometimes leaves no episode that isn't already on elsewhere.
        static let sameEpisodeLibraryTitles = 20
        /// How long a stretch of schedule the repeat check walks.
        static let repeatWindow: TimeInterval = 14 * 24 * ScheduleConstants.secondsPerHour
    }

    private static func report(for profile: SyntheticLibrary.Profile, limit: SimulcastLimit = .two) throws -> (LineupReport, LibraryIndex, [Channel]) {
        let index = LibraryIndex(items: SyntheticLibrary.items(profile))
        let options = LineupOptions.adapted(to: index, grid: .continuous)
        let lineup = LineupBuilder(curated: try ChannelCatalog.curated(), options: options)
            .build(index: index, customization: LineupCustomization(simulcastLimit: limit))
        return (LineupReport(lineup: lineup, index: index, simulcastLimit: limit), index, lineup)
    }

    @Test("Every title airs somewhere", arguments: SyntheticLibrary.Profile.all)
    func coverage(profile: SyntheticLibrary.Profile) throws {
        let (report, index, lineup) = try Self.report(for: profile)
        print("\n== \(profile)\n\(report)")
        let airing = Set(lineup.flatMap { $0.items.map { $0.seriesID ?? $0.id } })
        let missing = index.items.filter { $0.duration >= ScheduleConstants.minimumProgramDuration && !airing.contains($0.seriesID ?? $0.id) }
        #expect(missing.isEmpty, "\(missing.prefix(5).map(\.title))")
    }

    @Test("The same show is on no more channels at once than allowed", arguments: SyntheticLibrary.Profile.all)
    func simulcastLimit(profile: SyntheticLibrary.Profile) throws {
        let (report, _, _) = try Self.report(for: profile)
        guard report.titleCount >= Goal.simulcastLibraryTitles else { return }
        #expect(report.simulcastOverLimitShare <= Goal.simulcastOverLimitShare)
    }

    @Test("No episode or movie is on two channels at once", arguments: SyntheticLibrary.Profile.all)
    func noSameEpisode(profile: SyntheticLibrary.Profile) throws {
        for limit in [SimulcastLimit.two, .unlimited] {
            let (report, _, _) = try Self.report(for: profile, limit: limit)
            guard report.titleCount >= Goal.sameEpisodeLibraryTitles else { return }
            #expect(report.sameEpisodeShare == 0, "\(limit): \(report.sameEpisodeShare)")
        }
    }

    @Test("Channels are distinct, capped and numbered without gaps", arguments: SyntheticLibrary.Profile.all)
    func distinctAndNumbered(profile: SyntheticLibrary.Profile) throws {
        let (report, _, lineup) = try Self.report(for: profile)
        #expect(report.channelCount <= LineupOptions.Defaults.maximumChannels + LineupOptions.Defaults.maximumMarathonChannels)
        #expect(report.duplicateChannelPairs == 0)
        #expect(lineup.map(\.number) == Array(ChannelNumbering.automatic.lowerBound..<(ChannelNumbering.automatic.lowerBound + lineup.count)))
    }

    @Test("No episode repeats until its show has aired every episode on that channel", arguments: SyntheticLibrary.Profile.all)
    func noEarlyRepeats(profile: SyntheticLibrary.Profile) throws {
        let (_, _, lineup) = try Self.report(for: profile)
        let window = DateInterval(start: LineupReport.Tuning.referenceDate, duration: Goal.repeatWindow)
        for channel in lineup {
            let episodesPerShow = Dictionary(grouping: channel.items, by: \.showID).mapValues(\.count)
            var airedThisRun: [String: Set<String>] = [:]
            for program in channel.timeline.programs(overlapping: window) {
                let show = program.item.showID
                if airedThisRun[show, default: []].contains(program.item.id) {
                    #expect(airedThisRun[show]?.count == episodesPerShow[show], "\(channel.name): \(program.item.headline) repeated early")
                    airedThisRun[show] = []
                }
                airedThisRun[show, default: []].insert(program.item.id)
            }
        }
    }
}
