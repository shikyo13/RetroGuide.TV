import Foundation
import Testing
@testable import RetroGuideKit

@Suite("LineupBuilder")
struct LineupBuilderTests {
    private let comedy = ChannelDefinition(id: "c.comedy", number: 2, name: "Comedy", rule: ChannelRule(genres: ["Comedy"]), source: .curated)
    private let everything = ChannelDefinition(id: "c.all", number: 3, name: "Comedy Too", callSign: "COME", rule: ChannelRule(), source: .curated)
    private let horror = ChannelDefinition(id: "c.horror", number: 4, name: "Horror", rule: ChannelRule(genres: ["Horror"]), source: .curated)

    private let options = LineupOptions(minimumChannelRuntime: 3_600, minimumChannelItems: 2, marathonMinimumEpisodes: 1_000)
    private let index = LibraryIndex(items: TestFactory.show("Sitcom", episodes: 20, genres: ["Comedy"]))

    private func build(_ customization: LineupCustomization = LineupCustomization()) -> [Channel] {
        LineupBuilder(curated: [comedy, everything, horror], options: options).build(index: index, customization: customization)
    }

    @Test("Channels without enough content are dropped")
    func dropsThinChannels() {
        #expect(!build().map(\.id).contains(horror.id))
    }

    @Test("Channels airing identical content are de-duplicated, lowest number wins")
    func deduplicates() {
        let ids = build().map(\.id)
        #expect(ids.contains(comedy.id))
        #expect(!ids.contains(everything.id))
    }

    @Test("Hidden channels are kept but flagged")
    func hiddenFlag() throws {
        let channel = try #require(build(LineupCustomization(hiddenChannelIDs: [comedy.id])).first { $0.id == comedy.id })
        #expect(channel.isHidden)
    }

    @Test("Custom channels are included even when small")
    func customChannels() {
        let custom = ChannelDefinition(
            id: "custom.1",
            number: 500,
            name: "Mine",
            rule: ChannelRule(seriesIDs: ["server/sitcom"]),
            source: .custom
        )
        #expect(build(LineupCustomization(customChannels: [custom])).contains { $0.id == custom.id })
    }

    @Test("Call signs are made unique")
    func uniqueCallSigns() {
        var used: Set<String> = []
        #expect(CallSign.unique("ANIM", avoiding: &used) == "ANIM")
        #expect(CallSign.unique("ANIM", avoiding: &used) == "ANI2")
        #expect(CallSign.unique("ANIM", avoiding: &used) == "ANI3")
    }

    @Test("Call signs are derived from names")
    func callSignGeneration() {
        #expect(CallSign.make(from: "HBO") == "HBO")
        #expect(CallSign.make(from: "Comedy Central") == "CC")
        #expect(CallSign.make(from: "Showtime") == "SHOW")
    }
}

@Suite("ChannelCatalog")
struct ChannelCatalogTests {
    @Test("The bundled catalog loads with unique ids and numbers in the curated range")
    func catalogIsValid() throws {
        let catalog = try ChannelCatalog.curated()
        #expect(!catalog.isEmpty)
        #expect(Set(catalog.map(\.id)).count == catalog.count)
        #expect(Set(catalog.map(\.number)).count == catalog.count)
        #expect(catalog.allSatisfy { $0.number < ChannelNumbering.libraries.lowerBound })
        #expect(catalog.allSatisfy { [.curated, .decade].contains($0.source) })
    }
}
