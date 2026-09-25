import Foundation
import Testing
@testable import RetroGuideKit

@Suite("GenreTaxonomy")
struct GenreTaxonomyTests {
    private let taxonomy = GenreTaxonomy.shared

    @Test("Agent and language variants map to the same category", arguments: [
        ("Sci-Fi & Fantasy", GenreCategory.sciFi), ("Science Fiction", .sciFi), ("Komödie", .comedy),
        ("Comédie", .comedy), ("Documentaire", .documentary), ("Kids", .children), ("Talk Show", .talk),
    ])
    func variants(raw: String, expected: GenreCategory) {
        #expect(taxonomy.categories(for: [raw]).contains(expected))
    }

    @Test("Compound genres are split into their parts")
    func compound() {
        #expect(taxonomy.categories(for: ["Sci-Fi & Fantasy"]) == [.sciFi, .fantasy])
        #expect(taxonomy.categories(for: ["Crime Drama"]) == [.crime, .drama])
    }

    @Test("Unknown genres map to nothing")
    func unknown() {
        #expect(taxonomy.categories(for: ["Zzz Unknown"]).isEmpty)
    }

    @Test("Anime is detected from Japanese animation or the library name")
    func animeDetection() {
        #expect(AnimeDetector.isAnime(categories: [.animation], countries: ["Japan"], libraryTitle: "TV"))
        #expect(AnimeDetector.isAnime(categories: [.action], countries: [], libraryTitle: "My Anime"))
        #expect(!AnimeDetector.isAnime(categories: [.animation], countries: ["United States of America"], libraryTitle: "TV"))
    }

    @Test("Channel rules match on categories derived from raw genres")
    func ruleMatchesCategories() {
        let index = LibraryIndex(items: [
            TestFactory.episode("1", show: "Space", genres: ["Sci-Fi & Fantasy"]),
            TestFactory.episode("2", show: "Laughs", genres: ["Komödie"]),
        ])
        let titles = ChannelRule(categories: [.sciFi]).matchingItems(in: index).map(\.headline)
        #expect(titles == ["Space"])
    }
}

@Suite("Lineup scaling")
struct LineupScalingTests {
    @Test("Small libraries get a lower runtime threshold, large ones the full one")
    func adaptiveRuntime() {
        let small = LibraryIndex(items: TestFactory.show("Small", episodes: 20))
        let large = LibraryIndex(items: TestFactory.show("Large", episodes: 5_000))
        #expect(LineupOptions.adapted(to: small, grid: .continuous).minimumChannelRuntime == LineupOptions.Scaling.minimumChannelRuntime)
        #expect(LineupOptions.adapted(to: large, grid: .continuous).minimumChannelRuntime == LineupOptions.Defaults.minimumChannelRuntime)
    }

    @Test("The cap drops dynamic channels before curated ones")
    func cap() {
        let items = TestFactory.show("A", episodes: 30, genres: ["Comedy"]).map { $0 }
            + TestFactory.show("B", episodes: 30, genres: ["Drama"])
        let index = LibraryIndex(items: items)
        let curated = [
            ChannelDefinition(id: "c.comedy", number: 2, name: "Comedy", rule: ChannelRule(categories: [.comedy]), source: .curated),
            ChannelDefinition(id: "c.drama", number: 3, name: "Drama", rule: ChannelRule(categories: [.drama]), source: .curated),
        ]
        let options = LineupOptions(minimumChannelRuntime: 3_600, minimumChannelItems: 2, marathonMinimumEpisodes: 10, maximumChannels: 2)
        let sources = LineupBuilder(curated: curated, options: options)
            .build(index: index, customization: LineupCustomization())
            .map(\.definition.source)
        #expect(sources == [.curated, .curated])
    }

    @Test("Disabled groups are left out")
    func disabledSources() {
        let index = LibraryIndex(items: TestFactory.show("A", episodes: 30))
        let options = LineupOptions(minimumChannelRuntime: 3_600, minimumChannelItems: 2, marathonMinimumEpisodes: 10)
        let channels = LineupBuilder(curated: [], options: options)
            .build(index: index, customization: LineupCustomization(disabledSources: [.series]))
        #expect(!channels.contains { $0.definition.source == .series })
    }
}
