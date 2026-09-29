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
        /// Libraries with less content than this can't avoid repeats.
        static let freshnessLibraryHours = 24.0 * 14 * 10
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

    @Test("Channels are distinct, capped and numbered without gaps", arguments: SyntheticLibrary.Profile.all)
    func distinctAndNumbered(profile: SyntheticLibrary.Profile) throws {
        let (report, _, lineup) = try Self.report(for: profile)
        #expect(report.channelCount <= LineupOptions.Defaults.maximumChannels)
        #expect(report.duplicateChannelPairs == 0)
        #expect(lineup.map(\.number) == Array(ChannelNumbering.automatic.lowerBound..<(ChannelNumbering.automatic.lowerBound + lineup.count)))
    }

    @Test("Themed channels stay fresh and varied when the library allows", arguments: SyntheticLibrary.Profile.all)
    func freshness(profile: SyntheticLibrary.Profile) throws {
        let (report, index, _) = try Self.report(for: profile)
        let hours = index.items.reduce(0) { $0 + $1.duration } / ScheduleConstants.secondsPerHour
        guard hours >= Goal.freshnessLibraryHours else { return }
        #expect(report.repeatShortfalls.isEmpty, "\(report.repeatShortfalls)")
    }
}
