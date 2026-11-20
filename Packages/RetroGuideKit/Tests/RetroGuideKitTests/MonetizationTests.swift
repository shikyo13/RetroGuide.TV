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

    @Test("First request requires playback on two local calendar days, across launches")
    func firstRequest() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Chicago"))
        let first = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 20)))
        var pacing = RatingPromptPacing()
        pacing.recordWatching(60, at: first, calendar: calendar)
        pacing.recordWatching(3 * hour, at: first + 3 * hour, calendar: calendar)
        #expect(!pacing.isRequestDue(version: "1.2"))
        let saved = try JSONEncoder().encode(pacing)
        pacing = try JSONDecoder().decode(RatingPromptPacing.self, from: saved)
        pacing.recordWatching(.zero, at: first + 5 * hour, calendar: calendar)
        #expect(!pacing.isRequestDue(version: "1.2"))
        pacing.recordWatching(60, at: first + 5 * hour, calendar: calendar)
        #expect(pacing.isRequestDue(version: "1.2"))
    }

    @Test("Previously eligible viewers keep their first request")
    func keepsLegacyEligibility() throws {
        let saved = Data(#"{"watched":10800}"#.utf8)
        var pacing = try JSONDecoder().decode(RatingPromptPacing.self, from: saved)
        pacing.recordWatching(60)
        #expect(pacing.isRequestDue(version: "1.2"))
    }

    @Test("Next request after another 48 hours and 120 days, in a newer version")
    func laterRequests() {
        let asked = Date(timeIntervalSince1970: 1_800_000_000)
        let day: TimeInterval = 86_400
        var pacing = RatingPromptPacing(watched: 3 * hour)
        pacing.requested(version: "1.2", at: asked)
        pacing.recordWatching(48 * hour)
        #expect(!pacing.isRequestDue(version: "1.2", now: asked + 200 * day))
        #expect(!pacing.isRequestDue(version: "1.3", now: asked + 119 * day))
        #expect(pacing.isRequestDue(version: "1.3", now: asked + 120 * day))
    }

    @Test("Pacing saved by 1.8 still applies")
    func readsEarlierPacing() throws {
        let saved = Data(#"{"watched":10800,"watchedAtLastRequest":10800,"lastRequestedVersion":"1.8"}"#.utf8)
        var pacing = try JSONDecoder().decode(RatingPromptPacing.self, from: saved)
        #expect(!pacing.isRequestDue(version: "1.9"))
        pacing.recordWatching(48 * hour)
        #expect(pacing.isRequestDue(version: "1.9"))
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
