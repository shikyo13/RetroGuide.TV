import Foundation
import Testing
@testable import RetroGuideKit

@Suite("Lineup variety")
struct LineupVarietyTests {
    /// 45 comedy shows (big enough for the thin-channel rule): six distinct
    /// channels of seven shows each, plus "Show1" on every one of them.
    private let index = LibraryIndex(items: (1...45).flatMap { TestFactory.show("Show\($0)", episodes: 6, genres: ["Comedy"]) })
    private let options = LineupOptions(minimumChannelRuntime: 3_600, minimumChannelItems: 2, marathonMinimumEpisodes: 1_000)

    private var curated: [ChannelDefinition] {
        let everything = ChannelDefinition(id: "c.all", number: 1, name: "Everything", rule: ChannelRule(), source: .curated)
        let themed = (0..<6).map { block in
            let shows = [1] + (0..<7).map { 2 + block * 7 + $0 }
            return ChannelDefinition(
                id: "c.theme\(block)",
                number: block + 2,
                name: "Theme \(block)",
                rule: ChannelRule(seriesIDs: Set(shows.map { "\(TestFactory.serverID)/show\($0)" })),
                source: .curated
            )
        }
        return [everything] + themed
    }

    private func build(_ repeats: ShowRepeats) -> [Channel] {
        LineupBuilder(curated: curated, options: options)
            .build(index: index, customization: LineupCustomization(showRepeats: repeats))
            .filter { $0.definition.source == .curated }
    }

    private func themedCount(of show: String, in lineup: [Channel]) -> Int {
        lineup.filter { $0.id != "c.all" && $0.items.contains { $0.series?.title == show } }.count
    }

    @Test("Each show airs on at most the chosen number of themed channels", arguments: [ShowRepeats.fewer, .balanced, .more])
    func cap(repeats: ShowRepeats) throws {
        let lineup = build(repeats)
        let limit = try #require(repeats.channelLimit)
        for number in 1...45 {
            #expect(themedCount(of: "Show\(number)", in: lineup) <= limit)
        }
    }

    @Test("Every show keeps at least one themed channel")
    func coverage() {
        let lineup = build(.fewer)
        for number in 1...43 {
            #expect(themedCount(of: "Show\(number)", in: lineup) >= 1)
        }
    }

    @Test("Catch-all channels keep everything")
    func catchAllUntouched() throws {
        let everything = try #require(build(.fewer).first { $0.id == "c.all" })
        #expect(Set(everything.items.compactMap { $0.series?.title }).count == 45)
    }

    @Test("No limit keeps shows on every channel they fit")
    func unlimited() {
        let lineup = build(.unlimited)
        #expect(themedCount(of: "Show1", in: lineup) == 6)
    }
}
