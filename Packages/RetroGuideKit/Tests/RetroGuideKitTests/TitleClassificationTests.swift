import Foundation
import Testing
@testable import RetroGuideKit

@Suite("Title ids")
struct TitleIDsTests {
    @Test("Agent guids give IMDb, TMDB and TVDB ids")
    func parsesGuids() {
        let ids = TitleIDs(guids: ["imdb://tt0944947", "tmdb://1399", "tvdb://121361", "plex://show/5d9c086c46115600200aa2fe"])
        #expect(ids == TitleIDs(imdb: 944_947, tmdb: 1_399, tvdb: 121_361))
    }

    @Test("Guids without a public database id give nothing")
    func ignoresOthers() {
        #expect(TitleIDs(guids: ["plex://movie/5d776b59ad5437001f79c6f8", "imdb://nm0000138", "local://12"]) == nil)
    }
}

@Suite("Title classification")
struct TitleClassificationTests {
    private static func table(_ entries: [TitleClassification.Section: [UInt32: Set<GenreCategory>]]) throws -> TitleClassification {
        try TitleClassification(data: TitleClassification.encode(entries))
    }

    @Test("Looks titles up by IMDb, then TMDB for the title's kind, then TVDB")
    func lookups() throws {
        let table = try Self.table([
            .imdb: [10: [.drama], 20: [.comedy, .crime]],
            .tmdbMovie: [30: [.horror]],
            .tmdbShow: [30: [.documentary]],
            .tvdb: [40: [.western]],
        ])
        #expect(table.categories(for: TitleIDs(imdb: 20, tmdb: 30), kind: .episode) == [.comedy, .crime])
        #expect(table.categories(for: TitleIDs(imdb: 99, tmdb: 30), kind: .movie) == [.horror])
        #expect(table.categories(for: TitleIDs(tmdb: 30), kind: .episode) == [.documentary])
        #expect(table.categories(for: TitleIDs(tvdb: 40), kind: .episode) == [.western])
        #expect(table.categories(for: TitleIDs(tvdb: 40), kind: .movie) == nil)
        #expect(table.categories(for: TitleIDs(imdb: 11), kind: .movie) == nil)
    }

    @Test("Every category survives the round trip")
    func everyCategory() throws {
        let table = try Self.table([.imdb: [1: Set(GenreCategory.allCases)]])
        #expect(table.categories(for: TitleIDs(imdb: 1), kind: .movie) == Set(GenreCategory.allCases))
        #expect(TitleClassification.categoryBits.count == Set(TitleClassification.categoryBits).count)
        #expect(Set(TitleClassification.categoryBits) == Set(GenreCategory.allCases))
    }

    @Test("A damaged table isn't read")
    func rejectsGarbage() {
        #expect(throws: TitleClassification.TableError.self) { try TitleClassification(data: Data("nope".utf8)) }
    }

    @Test("The bundled table loads")
    func bundled() {
        #expect(!TitleClassification.shared.isEmpty)
    }
}

/// How a title's categories combine the server's tags with the classification,
/// checked the way channels see them: through rules.
@Suite("Classified titles on channels")
struct ClassifiedChannelTests {
    private static let crime = ChannelRule(categories: [.crime, .mystery], formats: [.scripted])
    private static let docs = ChannelRule(categories: [.documentary])

    private static func matches(_ rule: ChannelRule, _ item: MediaItem, classified: [UInt32: Set<GenreCategory>]) throws -> Bool {
        let table = try TitleClassification(data: TitleClassification.encode([.imdb: classified]))
        let index = LibraryIndex(items: [item], libraries: [], showAliases: [:], classification: table)
        return !rule.matchingItems(in: index).isEmpty
    }

    @Test("A documentary the server tags Mystery is unscripted, so it isn't on fiction channels")
    func documentaryTaggedMystery() throws {
        let fishing = TestFactory.episode("1", show: "River", genres: ["Documentary", "Mystery", "Reality"], titleIDs: TitleIDs(imdb: 1))
        #expect(try !Self.matches(Self.crime, fishing, classified: [1: [.documentary]]))
        #expect(try Self.matches(Self.docs, fishing, classified: [1: [.documentary]]))
    }

    @Test("A loosely applied tag counts only when the classification confirms it")
    func looseTags() throws {
        let wizard = TestFactory.movie("1", genres: ["Adventure", "Family", "Fantasy", "Mystery"], titleIDs: TitleIDs(imdb: 1))
        let classified: [UInt32: Set<GenreCategory>] = [1: [.adventure, .fantasy, .children]]
        #expect(try !Self.matches(ChannelRule(categories: [.mystery]), wizard, classified: classified))
        #expect(try Self.matches(ChannelRule(categories: [.fantasy]), wizard, classified: classified))
        #expect(try Self.matches(ChannelRule(categories: [.family]), wizard, classified: classified))
        // Not every server tag needs confirming: a detective show keeps "Crime".
        let detective = TestFactory.episode("2", show: "Detective", genres: ["Crime", "Mystery"], titleIDs: TitleIDs(imdb: 2))
        #expect(try Self.matches(Self.crime, detective, classified: [2: [.drama]]))
    }

    @Test("A server's game show tag makes a title unscripted even when the classification calls it comedy")
    func serverUnscripted() throws {
        let magic = TestFactory.episode("1", show: "Magic", genres: ["Comedy", "Game Show"], titleIDs: TitleIDs(imdb: 1))
        #expect(try !Self.matches(ChannelRule(categories: [.comedy], formats: [.scripted]), magic, classified: [1: [.comedy]]))
        #expect(try Self.matches(ChannelRule(categories: [.gameShow]), magic, classified: [1: [.comedy]]))
    }

    @Test("Partial server tags do not discard known food, travel, children or horror categories")
    func partialMetadata() throws {
        let food = TestFactory.episode("1", show: "Cooking", genres: ["Comedy"], titleIDs: TitleIDs(imdb: 1))
        let travel = TestFactory.episode("2", show: "Travelling", genres: ["Documentary"], titleIDs: TitleIDs(imdb: 2))
        let children = TestFactory.episode("3", show: "Children", genres: ["Animation"], titleIDs: TitleIDs(imdb: 3))
        let horror = TestFactory.movie("4", genres: ["Drama"], titleIDs: TitleIDs(imdb: 4))
        let classified: [UInt32: Set<GenreCategory>] = [1: [.food], 2: [.travel], 3: [.children], 4: [.horror]]
        for (item, category) in [(food, GenreCategory.food), (travel, .travel), (children, .children), (horror, .horror)] {
            #expect(try Self.matches(ChannelRule(categories: [category]), item, classified: classified))
        }
    }

    @Test("An untagged title takes the classification; an unknown one keeps its tags")
    func fallbacks() throws {
        let untagged = TestFactory.episode("1", show: "Bare", titleIDs: TitleIDs(imdb: 1))
        #expect(try Self.matches(Self.crime, untagged, classified: [1: [.crime]]))
        let unknown = TestFactory.episode("2", show: "Obscure", genres: ["Mystery"], titleIDs: TitleIDs(imdb: 99))
        #expect(try Self.matches(Self.crime, unknown, classified: [1: [.crime]]))
    }
}
