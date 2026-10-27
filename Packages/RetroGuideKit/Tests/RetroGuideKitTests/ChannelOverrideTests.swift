import Foundation
import Testing
@testable import RetroGuideKit

@Suite("Taking titles off a channel")
struct ChannelOverrideTests {
    private let comedy = ChannelDefinition(id: "c.comedy", number: 2, name: "Comedy", rule: ChannelRule(categories: [.comedy]), source: .curated)
    private let everything = ChannelDefinition(id: "c.all", number: 3, name: "Everything", rule: ChannelRule(), source: .curated)
    private let options = LineupOptions(minimumChannelRuntime: 3_600, minimumChannelItems: 2, marathonMinimumSeasons: 1_000)
    private let index = LibraryIndex(items: TestFactory.show("Sitcom", episodes: 20, genres: ["Comedy"])
        + TestFactory.show("Panel", episodes: 20, genres: ["Comedy"])
        + TestFactory.show("Saga", episodes: 20, genres: ["Drama"]))

    private func shows(on id: String, _ customization: LineupCustomization) -> Set<String> {
        let lineup = LineupBuilder(curated: [comedy, everything], options: options).build(index: index, customization: customization)
        return Set(lineup.first { $0.id == id }?.items.map(\.headline) ?? [])
    }

    @Test("A removed show leaves that channel only")
    func removesFromOneChannel() throws {
        let panel = try #require(index.items.first { $0.headline == "Panel" })
        let customization = LineupCustomization(removedTitles: [comedy.id: [panel.showID]])
        #expect(shows(on: comedy.id, customization) == ["Sitcom"])
        #expect(shows(on: everything.id, customization) == ["Sitcom", "Panel", "Saga"])
    }

    @Test("Saved settings without removed titles still load")
    func decodesOlderSettings() throws {
        let decoded = try JSONDecoder().decode(LineupCustomization.self, from: Data(#"{"hiddenChannelIDs": ["c.all"]}"#.utf8))
        #expect(decoded.removedTitles.isEmpty)
        #expect(decoded.hiddenChannelIDs == ["c.all"])
    }

    @Test("A placement names the channel's genres the title has, and where they came from")
    func explainsPlacement() throws {
        let sitcom = try #require(index.items.first { $0.headline == "Sitcom" })
        let placement = try #require(index.placement(of: sitcom, under: comedy.rule))
        #expect(placement.matchedCategories == [.comedy])
        #expect(placement.source == .server)
        #expect(placement.format == .scripted)
    }
}
