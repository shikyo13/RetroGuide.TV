import Foundation
import Testing
@testable import RetroGuideKit

/// Scores generated lineups for libraries of every shape and size against the
/// goals of channel generation, so no change can quietly make small, huge or
/// oddly organized libraries worse.
@Suite("Lineup bench")
struct LineupBenchTests {
    enum Goal {
        static let maximumChannels = 80
        /// Median across themed channels; every channel must also last a week or
        /// use up its content before repeating (``LineupReport/repeatShortfalls``).
        static let repeatDays = 14.0
        /// Libraries with less content than this can't avoid repeats.
        static let freshnessLibraryHours = 24.0 * 14 * 10
    }

    private static func report(for profile: SyntheticLibrary.Profile, repeats: ShowRepeats = .balanced) throws -> (LineupReport, LibraryIndex) {
        let index = LibraryIndex(items: SyntheticLibrary.items(profile))
        let options = LineupOptions.adapted(to: index, grid: .continuous)
        let lineup = LineupBuilder(curated: try ChannelCatalog.curated(), options: options)
            .build(index: index, customization: LineupCustomization(showRepeats: repeats))
        return (LineupReport(lineup: lineup, index: index), index)
    }

    @Test("Every title has a themed home", arguments: SyntheticLibrary.Profile.all)
    func coverage(profile: SyntheticLibrary.Profile) throws {
        let (report, _) = try Self.report(for: profile)
        print("\n== \(profile)\n\(report)")
        #expect(report.uncoveredTitles.isEmpty, "\(report.uncoveredTitles.prefix(5))")
    }

    @Test("Repeats stay within the chosen limit", arguments: SyntheticLibrary.Profile.all)
    func repeatLimit(profile: SyntheticLibrary.Profile) throws {
        let (report, _) = try Self.report(for: profile)
        #expect(report.themedChannelsPerTitleMax <= (ShowRepeats.balanced.channelLimit ?? .max))
    }

    @Test("Channels are distinct and the lineup stays lean", arguments: SyntheticLibrary.Profile.all)
    func distinctAndLean(profile: SyntheticLibrary.Profile) throws {
        let (report, _) = try Self.report(for: profile)
        #expect(report.channelCount <= Goal.maximumChannels)
        #expect(report.duplicateChannelPairs == 0)
    }

    @Test("Themed channels stay fresh and varied when the library allows", arguments: SyntheticLibrary.Profile.all)
    func freshness(profile: SyntheticLibrary.Profile) throws {
        let (report, index) = try Self.report(for: profile)
        let hours = index.items.reduce(0) { $0 + $1.duration } / ScheduleConstants.secondsPerHour
        guard hours >= Goal.freshnessLibraryHours else { return }
        #expect(report.repeatDaysMedian >= Goal.repeatDays)
        #expect(report.repeatShortfalls.isEmpty, "\(report.repeatShortfalls)")
        #expect(report.varietyShortfalls.isEmpty, "\(report.varietyShortfalls)")
    }
}
