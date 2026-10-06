import Foundation
import Testing
@testable import RetroGuideKit

@Suite("ProAccess")
struct ProAccessTests {
    private let free = ProAccess(isPro: false)
    private let pro = ProAccess(isPro: true)

    @Test("Free allows one server, Pro any number")
    func servers() {
        #expect(free.canAddServer(connectedCount: 0))
        #expect(!free.canAddServer(connectedCount: 1))
        #expect(pro.canAddServer(connectedCount: 5))
    }

    @Test("Free allows one custom channel, Pro any number")
    func customChannels() {
        #expect(free.canCreateCustomChannel(existingCount: 0))
        #expect(!free.canCreateCustomChannel(existingCount: 1))
        #expect(pro.canCreateCustomChannel(existingCount: 20))
    }

    @Test("Scheduling controls and ad-free viewing are Pro")
    func proOnly() {
        #expect(!free.canChangeScheduling)
        #expect(pro.canChangeScheduling)
        #expect(free.showsAds)
        #expect(!pro.showsAds)
    }
}

@Suite("AdPacing")
struct AdPacingTests {
    private let minute = ScheduleConstants.secondsPerMinute

    @Test("No full-screen ad until 90 minutes of watching")
    func dueAfterInterval() {
        var pacing = AdPacing()
        pacing.recordWatching(89 * minute)
        #expect(!pacing.isInterstitialDue)
        pacing.recordWatching(minute)
        #expect(pacing.isInterstitialDue)
    }

    @Test("Showing an ad starts the next 90 minutes")
    func resetsWhenShown() {
        var pacing = AdPacing(watchedSinceInterstitial: 2 * AdPacing.interstitialInterval)
        pacing.interstitialShown()
        #expect(!pacing.isInterstitialDue)
        #expect(pacing.watchedSinceInterstitial == .zero)
    }

    @Test("Negative or zero durations are ignored")
    func ignoresInvalidDurations() {
        var pacing = AdPacing(watchedSinceInterstitial: -5)
        pacing.recordWatching(-minute)
        pacing.recordWatching(.zero)
        #expect(pacing.watchedSinceInterstitial == .zero)
    }

    @Test("Survives a save and restore")
    func codable() throws {
        var pacing = AdPacing()
        pacing.recordWatching(42 * minute)
        let restored = try JSONDecoder().decode(AdPacing.self, from: JSONEncoder().encode(pacing))
        #expect(restored == pacing)
    }
}

@Suite("RatingPromptPacing")
struct RatingPromptPacingTests {
    private let hour = ScheduleConstants.secondsPerHour

    @Test("First request after three hours of watching")
    func firstRequest() {
        var pacing = RatingPromptPacing()
        pacing.recordWatching(3 * hour - 1)
        #expect(!pacing.isRequestDue(version: "1.2"))
        pacing.recordWatching(1)
        #expect(pacing.isRequestDue(version: "1.2"))
    }

    @Test("Next request after another 48 hours, in a newer version")
    func laterRequests() {
        var pacing = RatingPromptPacing(watched: 3 * hour)
        pacing.requested(version: "1.2")
        pacing.recordWatching(48 * hour)
        #expect(!pacing.isRequestDue(version: "1.2"))
        #expect(pacing.isRequestDue(version: "1.3"))
    }

    @Test("A new version alone doesn't make a request due")
    func newVersionNeedsWatching() {
        var pacing = RatingPromptPacing(watched: 3 * hour)
        pacing.requested(version: "1.2")
        pacing.recordWatching(47 * hour)
        #expect(!pacing.isRequestDue(version: "1.3"))
    }

    @Test("Negative or zero durations are ignored")
    func ignoresInvalidDurations() {
        var pacing = RatingPromptPacing(watched: -5)
        pacing.recordWatching(-hour)
        pacing.recordWatching(.zero)
        #expect(pacing.watched == .zero)
    }

    @Test("Survives a save and restore")
    func codable() throws {
        var pacing = RatingPromptPacing()
        pacing.recordWatching(4 * hour)
        pacing.requested(version: "1.2")
        let restored = try JSONDecoder().decode(RatingPromptPacing.self, from: JSONEncoder().encode(pacing))
        #expect(restored == pacing)
    }
}
