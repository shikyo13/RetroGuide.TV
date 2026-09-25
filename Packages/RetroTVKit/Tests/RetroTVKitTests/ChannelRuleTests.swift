import Foundation
import Testing
@testable import RetroTVKit

@Suite("ChannelRule")
struct ChannelRuleTests {
    private let index = LibraryIndex(items: [
        TestFactory.episode("1", show: "Sitcom", genres: ["Comedy"], networks: ["NBC"], rating: "TV-PG", year: 1994),
        TestFactory.episode("2", show: "Cartoon", genres: ["Animation", "Comedy"], rating: "TV-Y7", year: 1992),
        TestFactory.episode("3", show: "Anime", genres: ["Animation", "Anime"], rating: "TV-14", year: 2004),
        TestFactory.movie("4", genres: ["Horror"], year: 1987),
    ])

    private func titles(_ rule: ChannelRule) -> Set<String> {
        Set(rule.matchingItems(in: index).map(\.headline))
    }

    @Test("An empty rule matches everything")
    func emptyRule() {
        #expect(ChannelRule().matchingItems(in: index).count == index.items.count)
    }

    @Test("Values within a criterion are OR-ed")
    func orWithinCriterion() {
        #expect(titles(ChannelRule(genres: ["Horror", "Anime"])) == ["Anime", "Movie 4"])
    }

    @Test("Criteria are AND-ed")
    func andAcrossCriteria() {
        #expect(titles(ChannelRule(genres: ["Comedy"], audiences: [.kids])) == ["Cartoon"])
    }

    @Test("Excluded genres remove matches")
    func exclusion() {
        #expect(titles(ChannelRule(genres: ["Animation"], excludedGenres: ["Anime"])) == ["Cartoon"])
    }

    @Test("Matching is case and diacritic insensitive")
    func normalization() {
        #expect(titles(ChannelRule(genres: ["cOMEDY"], networks: ["nbc"])) == ["Sitcom"])
    }

    @Test("Decades and kinds filter correctly")
    func decadesAndKinds() {
        #expect(titles(ChannelRule(kinds: [.episode], decades: [1990])) == ["Sitcom", "Cartoon"])
        #expect(titles(ChannelRule(kinds: [.movie], decades: [1980])) == ["Movie 4"])
    }

    @Test("Keywords search show and episode titles")
    func keywords() {
        #expect(titles(ChannelRule(keywords: ["cartoon"])) == ["Cartoon"])
    }
}

@Suite("Audience")
struct AudienceTests {
    @Test("Known ratings map to buckets", arguments: [
        (String?("TV-Y7"), Audience.kids), ("PG", .family), ("TV-14", .teen), ("R", .mature),
        ("gb/15", .mature), ("gb/U", .family), (nil, .unrated), ("NR", .unrated),
    ])
    func classification(rating: String?, expected: Audience) {
        #expect(Audience.classify(rating: rating) == expected)
    }

    @Test("Unknown ratings fall back to certificate age")
    func ageFallback() {
        #expect(Audience.classify(rating: "xx/unknown", age: 6) == .kids)
        #expect(Audience.classify(rating: "de/16") == .teen)
    }
}
