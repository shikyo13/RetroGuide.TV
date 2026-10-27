import Foundation
import Testing
@testable import RetroGuideKit

@Suite("Personal viewing")
struct ViewingFeaturesTests {
    private func channel() -> Channel {
        Channel(definition: .init(id: "new", number: 1, name: "Test", rule: .init(), source: .custom), items: [], isHidden: false,
                timeline: ChannelTimeline(channelID: "new", items: [], ordering: .shuffle, grid: .continuous), formerIDs: ["old"])
    }
    @Test func favoriteMigrationAndRemoval() {
        var choices = ViewingPreferences()
        choices.favoriteIDs = ["old", "offline"]
        #expect(choices.isFavorite(channel()))
        choices.toggleFavorite(channel())
        #expect(choices.favoriteIDs == ["offline"])
        choices.toggleFavorite(channel())
        #expect(choices.favoriteIDs == ["new", "offline"])
    }
    @Test func recentChannelsAreBoundedAndUnique() {
        var choices = ViewingPreferences()
        for n in 0..<100 { choices.remember(String(n)) }
        choices.remember("95")
        #expect(choices.recentChannelIDs.count == ViewingPreferences.Limits.recentChannels)
        #expect(choices.recentChannelIDs.first == "95")
        #expect(Set(choices.recentChannelIDs).count == choices.recentChannelIDs.count)
    }
    @Test func timerClampsCustomDuration() {
        let now = Date(timeIntervalSince1970: 100)
        #expect(SleepDeadline.duration(minutes: -1, now: now).timeIntervalSince(now) == 60)
        #expect(SleepDeadline.duration(minutes: 999, now: now).timeIntervalSince(now) == 240 * 60)
        #expect(SleepDeadline.endOfProgram(nil, now: now) == nil)
    }
}
