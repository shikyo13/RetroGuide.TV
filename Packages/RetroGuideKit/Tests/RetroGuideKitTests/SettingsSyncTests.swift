import Foundation
import Testing
@testable import RetroGuideKit

@Suite("Shared configuration sync")
struct SettingsSyncTests {
    private let firstDevice = "00000000-0000-0000-0000-000000000001"
    private let secondDevice = "00000000-0000-0000-0000-000000000002"

    private func merge(_ source: SettingsReplica, into target: inout SettingsReplica) throws {
        for record in source.records.values { try target.merge(record) }
    }

    private func values(_ ids: Set<String>) throws -> SettingsValues {
        var settings = SharedSettings()
        settings.favoriteIDs = ids
        return try settings.encoded()
    }

    @Test("Offline edits to different favorites are combined")
    func independentFavorites() throws {
        let initial = try values(["existing"])
        var a = SettingsReplica(device: firstDevice)
        try a.capture(initial, comparedTo: SettingsValues())
        var b = SettingsReplica(device: secondDevice)
        try merge(a, into: &b)
        try a.capture(values(["existing", "phone"]), comparedTo: initial)
        try b.capture(values(["existing", "tv"]), comparedTo: initial)
        let sentA = a
        try merge(b, into: &a)
        try merge(sentA, into: &b)
        #expect(a.values == b.values)
        #expect(try SharedSettings(values: a.values).favoriteIDs == ["existing", "phone", "tv"])
    }

    @Test("An old offline copy does not resurrect a removed favorite")
    func retainedDeletion() throws {
        let initial = try values(["removed", "kept"])
        var a = SettingsReplica(device: firstDevice)
        try a.capture(initial, comparedTo: SettingsValues())
        let oldCopy = a
        try a.capture(values(["kept"]), comparedTo: initial)
        try merge(oldCopy, into: &a)
        #expect(try SharedSettings(values: a.values).favoriteIDs == ["kept"])
        let persisted = try JSONDecoder().decode(SettingsReplica.self, from: JSONEncoder().encode(a))
        #expect(persisted.records[SettingsValues.key("favorites", "removed")]?.value == nil)
        #expect(persisted.records.count == a.records.count)
    }

    @Test("Same-setting concurrent edits converge regardless of arrival order")
    func conflictConvergence() throws {
        var baseline = SettingsValues()
        try baseline.put("classic", "theme")
        var a = SettingsReplica(device: firstDevice)
        try a.capture(baseline, comparedTo: SettingsValues())
        var b = SettingsReplica(device: secondDevice)
        try merge(a, into: &b)
        var aEdit = baseline
        try aEdit.put("green", "theme")
        var bEdit = baseline
        try bEdit.put("purple", "theme")
        try a.capture(aEdit, comparedTo: baseline)
        try b.capture(bEdit, comparedTo: baseline)
        let oldA = a
        try merge(b, into: &a)
        try merge(oldA, into: &b)
        #expect(a.values == b.values)
        #expect(try a.values.get(String.self, "theme") == "purple")
        // An edit made after seeing the winner must win over both.
        var latest = a.values
        try latest.put("amber", "theme")
        try a.capture(latest, comparedTo: a.values)
        try merge(a, into: &b)
        #expect(try b.values.get(String.self, "theme") == "amber")
    }

    @Test("An in-flight upload cannot acknowledge a more recent local edit")
    func newerEditSurvivesAcknowledgement() throws {
        var a = SettingsReplica(device: firstDevice)
        var initial = SettingsValues()
        try initial.put(true, "favorite")
        try a.capture(initial, comparedTo: SettingsValues())
        let sent = try #require(a.records["favorite"])
        try a.capture(SettingsValues(), comparedTo: initial)
        a.acknowledge(sent)
        #expect(a.pending.contains("favorite"))
        a.acknowledge(try #require(a.records["favorite"]))
        #expect(a.pending.isEmpty)
    }

    @Test("Settings unavailable locally are retained until explicitly edited")
    func unavailableServerAndPendingParentalPolicy() throws {
        var cloud = SharedSettings()
        cloud.libraries = ["unreachable": ["library"]]
        cloud.parentalPolicy = ParentalPolicy()
        var a = SettingsReplica(device: firstDevice)
        try a.capture(cloud.encoded(), comparedTo: SettingsValues())
        let localBefore = try values([])
        let localAfter = try values(["favorite"])
        try a.capture(localAfter, comparedTo: localBefore)
        let shared = try SharedSettings(values: a.values)
        #expect(shared.libraries == cloud.libraries)
        #expect(shared.parentalPolicy != nil)
    }

    @Test("Choosing this device's setup explicitly removes old cloud entries")
    func deliberateReplacement() throws {
        var a = SettingsReplica(device: firstDevice)
        try a.capture(values(["old"]), comparedTo: SettingsValues())
        try a.capture(values(["chosen"]), comparedTo: a.values)
        #expect(try SharedSettings(values: a.values).favoriteIDs == ["chosen"])
        #expect(a.records[SettingsValues.key("favorites", "old")]?.value == nil)
    }

    private func channel(_ id: String, number: Int = 500) -> ChannelDefinition {
        ChannelDefinition(id: id, number: number, name: id,
            rule: ChannelRule(libraryIDs: ["plex/a", "jellyfin/b"], genres: ["Science", "Documentary"]),
            ordering: .marathon, source: .custom)
    }

    @Test("Lineups, per-channel edits and commercials round trip without media")
    func sharedChoicesRoundTrip() throws {
        var s = SharedSettings()
        s.lineup = LineupCustomization(hiddenChannelIDs: ["a"], orderingOverrides: ["b": .syndication],
            defaultOrdering: .blockShuffle, simulcastLimit: .two,
            customChannels: [channel("custom.one")], disabledSources: [.decade], removedTitles: ["a": ["title"]])
        s.favoriteIDs = ["a", "b"]
        s.commercials.isEnabled = true
        s.commercials.libraryIDs = ["clips/one", "clips/two"]
        s.commercials.count = .three
        s.subtitleRules["show/test"] = .off
        s.subtitleOffsets["show/test"] = 1.5
        let restored = try SharedSettings(values: s.encoded())
        #expect(restored.lineup == s.lineup)
        #expect(restored.commercials == s.commercials)
        #expect(restored.favoriteIDs == s.favoriteIDs)
        #expect(restored.subtitleRules == s.subtitleRules)
        #expect(restored.subtitleOffsets == s.subtitleOffsets)
        #expect(restored.themeID == nil)
    }

    @Test("The parental lineup stays separate and the lock is never exported")
    func parentalIsolation() throws {
        var s = SharedSettings()
        s.lineup.customChannels = [channel("custom.regular")]
        var policy = ParentalPolicy()
        policy.isEnabled = true
        policy.usesCustomLineup = true
        policy.channelCustomization.customChannels = [channel("custom.learning")]
        policy.maximumMovieRating = .g
        s.parentalPolicy = policy
        let restored = try SharedSettings(values: s.encoded())
        #expect(restored.parentalPolicy?.isEnabled == false)
        #expect(restored.parentalPolicy?.maximumMovieRating == .g)
        #expect(restored.parentalPolicy?.channelCustomization.customChannels.map(\.id) == ["custom.learning"])
        #expect(restored.lineup.customChannels.map(\.id) == ["custom.regular"])
    }

    @Test("Re-decoding unordered selections produces no spurious local edits")
    func stableRepresentation() throws {
        var s = SharedSettings()
        s.lineup.customChannels = [channel("custom.one")]
        s.parentalPolicy = ParentalPolicy()
        s.parentalPolicy?.libraryIDs = ["one", "two", "three"]
        let encoded = try s.encoded()
        for _ in 0..<12 { #expect(try SharedSettings(values: encoded).encoded() == encoded) }
    }

    @Test("Simultaneous channel creation keeps both channels with unique numbers")
    func duplicateNumbers() throws {
        var s = SharedSettings()
        s.lineup.customChannels = [channel("custom.z"), channel("custom.a")]
        let first = try SharedSettings(values: s.encoded()).lineup.customChannels
        s.lineup.customChannels.reverse()
        let second = try SharedSettings(values: s.encoded()).lineup.customChannels
        #expect(first == second)
        #expect(Set(first.map(\.id)).count == 2)
        #expect(Set(first.map(\.number)).count == 2)
    }

    @Test("Oversized changes are rejected without partial edits")
    func oversizedRecord() throws {
        var a = SettingsReplica(device: firstDevice)
        let good = try values(["saved"])
        try a.capture(good, comparedTo: SettingsValues())
        var bad = good
        try bad.put(String(repeating: "x", count: SettingsReplica.Limits.recordBytes + 1), "tooLarge")
        #expect(throws: SettingsReplica.Failure.self) { try a.capture(bad, comparedTo: good) }
        #expect(a.values == good)
    }

    @Test("Unknown future settings survive edits by an older client")
    func preservesUnknownFields() throws {
        var a = SettingsReplica(device: firstDevice)
        var cloud = try values(["saved"])
        try cloud.put("future", "newSetting")
        try a.capture(cloud, comparedTo: SettingsValues())
        try a.capture(values(["saved", "next"]), comparedTo: values(["saved"]))
        #expect(try a.values.get(String.self, "newSetting") == "future")
    }
    @Test("Restoring a device backup gives new edits an independent writer")
    func restoredWriter() throws {
        var original = SettingsReplica(device: firstDevice)
        let before = try values(["existing"])
        try original.capture(before, comparedTo: SettingsValues())
        var restored = try JSONDecoder().decode(SettingsReplica.self, from: JSONEncoder().encode(original))
        restored.startNewSession()
        #expect(restored.device != original.device)
        #expect(restored.records == original.records)
        #expect(restored.pending == original.pending)
        try original.capture(values(["existing", "original"]), comparedTo: before)
        try restored.capture(values(["existing", "restored"]), comparedTo: before)
        let saved = original
        try merge(restored, into: &original)
        try merge(saved, into: &restored)
        #expect(original.values == restored.values)
    }

    @Test("Contradictory values with the same revision cannot silently diverge")
    func rejectsAmbiguousRevision() throws {
        var replica = SettingsReplica(device: firstDevice)
        let revision = SettingsRevision(counter: 1, device: firstDevice)
        try replica.merge(SyncedSetting(key: "favorite", revision: revision, value: Data("true".utf8)))
        #expect(throws: SettingsReplica.Failure.self) {
            try replica.merge(SyncedSetting(key: "favorite", revision: revision, value: nil))
        }
    }

}
