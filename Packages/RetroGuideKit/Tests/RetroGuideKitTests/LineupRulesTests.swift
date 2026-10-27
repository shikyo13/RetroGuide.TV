import Foundation
import Testing
@testable import RetroGuideKit

@Suite("Lineup rules")
struct LineupRulesTests {
    private static func show(_ name: String, years: [Int], genres: [String] = ["Comedy"]) -> [MediaItem] {
        years.enumerated().map { number, year in
            TestFactory.episode("\(name)-\(number)", show: name, number: number + 1, genres: genres, year: year)
        }
    }

    private static func decadeChannel(_ id: String, _ number: Int, _ name: String, _ decades: Set<Int>) -> ChannelDefinition {
        ChannelDefinition(id: id, number: number, name: name, rule: ChannelRule(kinds: [.episode], decades: decades), source: .decade)
    }

    private static let decadeChannels = [
        decadeChannel("tv70", 1, "Classic TV", [1950, 1960, 1970]),
        decadeChannel("tv80", 2, "Totally 80s TV", [1980]),
        decadeChannel("tv90", 3, "90s Rewind", [1990]),
        decadeChannel("tv00", 4, "Y2K TV", [2000]),
    ]

    private static let options = LineupOptions(minimumChannelRuntime: 600, minimumChannelItems: 1, titleMinimumLibraryTitles: 1)

    /// The decade channels of the lineup built from `items`.
    private static func lineup(_ items: [MediaItem]) -> [Channel] {
        LineupBuilder(curated: decadeChannels, options: options)
            .build(index: LibraryIndex(items: items), customization: LineupCustomization())
            .filter { $0.definition.source == .decade }
    }

    @Test("A show is on the decade channel where most of its episodes aired")
    func majorityDecade() {
        // 6 episodes in the 70s, 2 in the 80s: 70s only.
        let items = Self.show("Mash", years: [1976, 1977, 1978, 1979, 1979, 1979, 1981, 1982])
            + Self.show("A", years: [1975, 1975]) + Self.show("B", years: [1972, 1972])
        let lineup = Self.lineup(items)
        #expect(lineup.map(\.name) == ["Classic TV"])
        #expect(Set(lineup[0].items.map(\.headline)) == ["Mash", "A", "B"])
    }

    @Test("Thin neighbouring decade channels merge; a healthy one stays on its own")
    func mergesThinRuns() {
        let items = Self.show("A", years: [1985]) + Self.show("B", years: [1991]) + Self.show("C", years: [1993])
            + Self.show("D", years: [2001]) + Self.show("E", years: [2002]) + Self.show("F", years: [2003])
        let lineup = Self.lineup(items)
        #expect(lineup.map(\.name) == ["80s–90s TV", "Y2K TV"])
        #expect(lineup[0].formerIDs == ["tv80", "tv90"])
    }

    @Test("A merged run that is still thin is dropped")
    func dropsThinRun() {
        let items = Self.show("A", years: [1985]) + Self.show("D", years: [2001]) + Self.show("E", years: [2002]) + Self.show("F", years: [2003])
        #expect(Self.lineup(items).map(\.name) == ["Y2K TV"])
    }

    @Test("Specials don't pull a show into another decade")
    func specialsDontVote() {
        var items = Self.show("A", years: [1995, 1996])
        items += (0..<5).map { TestFactory.episode("A-s\($0)", show: "A", season: 0, number: $0 + 1, year: 2010) }
        items += Self.show("B", years: [1992]) + Self.show("C", years: [1999])
        #expect(Self.lineup(items).map(\.name) == ["90s Rewind"])
    }

    @Test("When there are more channels than places, each kind keeps its first-pass allowance")
    func allowances() {
        let genres = (0..<40).map { number -> (ChannelDefinition, [MediaItem]) in
            (ChannelDefinition(id: "g\(number)", number: number, name: "G\(number)", rule: ChannelRule(genres: ["x"]), source: .curated), [])
        }
        let networks = (0..<40).map { number -> (ChannelDefinition, [MediaItem]) in
            (ChannelDefinition(id: "n\(number)", number: number, name: "N\(number)", rule: ChannelRule(networks: ["n\(number)"]), source: .network),
             TestFactory.show("S\(number)", episodes: 1))
        }
        let chosen = LineupSelection.select(genres + networks, capacity: 50)
        let counts = Dictionary(grouping: chosen) { ChannelCategory($0.definition) }.mapValues(\.count)
        // 24 genre and 16 network first, then the last 10 alternate.
        #expect(counts[.genre] == 29)
        #expect(counts[.network] == 21)
    }
}
