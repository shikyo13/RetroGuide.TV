import Foundation
import Testing
@testable import RetroGuideKit

@Suite("Separate parental lineup")
struct ParentalLineupTests {
    let regular = LineupCustomization(hiddenChannelIDs: ["hidden"], orderingOverrides: ["custom.regular": .shuffle],
        customChannels: [ChannelDefinition(id: "custom.regular", number: 901, name: "Regular", rule: ChannelRule(), source: .custom)])

    var policy: ParentalPolicy {
        var value = ParentalPolicy()
        value.isEnabled = true
        value.usesCustomLineup = true
        value.channelCustomization.customChannels = [ChannelDefinition(id: "custom.parental", number: 902,
            name: "Learning", rule: ChannelRule(collections: ["Learning"]), source: .custom)]
        return value
    }

    func snapshot(_ server: String) -> LibrarySnapshot {
        let items = ["G", "R"].enumerated().map { offset, rating in
            MediaItem(serverID: server, itemKey: "movie\(offset)", libraryID: "\(server)/movies", kind: .movie,
                title: "Movie \(offset)", duration: 3600, contentRating: rating, genres: ["Documentary"],
                collections: ["Learning"], publicIDs: TitleIDs(imdb: UInt32(offset + 1)))
        }
        return LibrarySnapshot(serverID: server, serverName: server, libraries: [], items: items)
    }

    @Test("Custom lineup replaces all automatic and regular custom channels")
    func isolatedLineup() throws {
        let p = policy
        let sources = [snapshot("plex"), snapshot("jellyfin")]
        for snapshots in [sources, sources.reversed()] {
            let index = LibraryIndex(snapshots: p.filtering(snapshots))
            let builder = LineupBuilder(curated: try ChannelCatalog.curated())
            let lineup = builder.build(index: index, customization: p.activeCustomization(regular: regular))
            #expect(lineup.map(\.id) == ["custom.parental"])
            #expect(lineup.flatMap(\.items).allSatisfy { $0.contentRating == "G" })
            #expect(lineup.first?.items.count == 1)
        }
    }

    @Test("Empty, unavailable or restricted custom channels never fall back to regular channels")
    func noFallback() throws {
        let builder = LineupBuilder(curated: try ChannelCatalog.curated())
        var p = policy
        let index = LibraryIndex(snapshots: p.filtering([snapshot("plex")]))
        p.channelCustomization.customChannels = []
        #expect(builder.build(index: index, customization: p.activeCustomization(regular: regular)).isEmpty)
        p = policy
        p.channelCustomization.customChannels[0].rule.collections = ["Missing"]
        #expect(builder.build(index: index, customization: p.activeCustomization(regular: regular)).isEmpty)
        p = policy; p.allLibraries = false
        let empty = LibraryIndex(snapshots: p.filtering([snapshot("plex")]))
        #expect(builder.build(index: empty, customization: p.activeCustomization(regular: regular)).isEmpty)
    }

    @Test("Switching back restores all regular customization and keeps parental channels")
    func restoreAndPersist() throws {
        var p = policy
        let saved = try JSONDecoder().decode(ParentalPolicy.self, from: JSONEncoder().encode(p))
        #expect(saved == p)
        p.isEnabled = false
        #expect(p.activeCustomization(regular: regular) == regular)
        #expect(p.channelCustomization.customChannels.count == 1)
        p.isEnabled = true; p.usesCustomLineup = false
        #expect(p.activeCustomization(regular: regular) == regular)
        p.usesCustomLineup = true
        #expect(p.activeCustomization(regular: regular).customChannels == saved.channelCustomization.customChannels)
    }

    @Test("Existing policies keep the regular lineup")
    func migration() throws {
        var fields = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(policy)) as? [String: Any])
        fields.removeValue(forKey: "usesCustomLineup")
        fields.removeValue(forKey: "channelCustomization")
        let old = try JSONDecoder().decode(ParentalPolicy.self, from: JSONSerialization.data(withJSONObject: fields))
        #expect(!old.usesCustomLineup)
        #expect(old.activeCustomization(regular: regular) == regular)
    }
}
