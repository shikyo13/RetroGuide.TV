import Foundation
import Testing
@testable import RetroGuideKit

@Suite("Program search")
struct ProgramSearchTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private var channels: [Channel] {
        let comedy = TestFactory.show("Seinfeld", episodes: 6) + TestFactory.show("Scrubs", episodes: 6)
        let drama = TestFactory.show("The Wire", episodes: 6)
        return [
            Channel(definition: ChannelDefinition(id: "c", number: 2, name: "Comedy", rule: ChannelRule(), source: .curated),
                    items: comedy, isHidden: false, grid: .continuous),
            Channel(definition: ChannelDefinition(id: "d", number: 3, name: "Drama", rule: ChannelRule(), source: .curated),
                    items: drama, isHidden: false, grid: .continuous),
        ]
    }

    @Test("Prefix matches come before substring matches")
    func ordering() {
        let results = ProgramSearchIndex(channels: channels).search("s", at: now)
        #expect(results.map(\.title.title).prefix(2) == ["Scrubs", "Seinfeld"])
    }

    @Test("Results carry the channel and the soonest airing within the horizon")
    func airing() throws {
        let result = try #require(ProgramSearchIndex(channels: channels).search("wire", at: now).first)
        #expect(result.title.title == "The Wire")
        #expect(result.channel?.id == "d")
        let airing = try #require(result.airing)
        #expect(airing.slotEnd > now)
        #expect(airing.item.headline == "The Wire")
    }

    @Test("Matching ignores case and accents; empty queries return nothing")
    func normalization() {
        let index = ProgramSearchIndex(channels: channels)
        #expect(index.search("SEÍNFELD", at: now).count == 1)
        #expect(index.search("  ", at: now).isEmpty)
    }

    @Test("Word starts rank above matches inside words")
    func wordStartRanking() {
        let index = ProgramSearchIndex(channels: channels)
        // "wi": "The Wire" (word start) should rank above any mid-word match.
        #expect(index.search("wi", at: now).first?.title.title == "The Wire")
    }
}
