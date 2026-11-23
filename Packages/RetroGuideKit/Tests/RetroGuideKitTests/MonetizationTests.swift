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
    private let minute = ScheduleConstants.secondsPerMinute
    private let day: TimeInterval = 86_400

    private func chicagoEvening() throws -> (Calendar, Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Chicago"))
        let evening = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 20)))
        return (calendar, evening)
    }

    @Test("First request after half an hour of watching, across launches")
    func firstRequestAfterHalfAnHour() throws {
        let (calendar, evening) = try chicagoEvening()
        var pacing = RatingPromptPacing()
        pacing.recordWatching(29 * minute, at: evening, calendar: calendar)
        #expect(!pacing.isRequestDue(version: "1.2"))
        pacing = try JSONDecoder().decode(RatingPromptPacing.self, from: JSONEncoder().encode(pacing))
        pacing.recordWatching(minute, at: evening + hour, calendar: calendar)
        #expect(pacing.isRequestDue(version: "1.2"))
    }

    @Test("First request on the second day of watching, however little was watched")
    func firstRequestOnSecondDay() throws {
        let (calendar, evening) = try chicagoEvening()
        var pacing = RatingPromptPacing()
        pacing.recordWatching(5 * minute, at: evening, calendar: calendar)
        pacing.recordWatching(minute, at: evening + 3 * hour, calendar: calendar)
        #expect(!pacing.isRequestDue(version: "1.2"))
        pacing.recordWatching(minute, at: evening + 5 * hour, calendar: calendar)
        #expect(pacing.isRequestDue(version: "1.2"))
    }

    @Test("One follow-up a week later after two more hours, then only rarely and in a newer version")
    func followUpThenRarely() {
        let asked = Date(timeIntervalSince1970: 1_800_000_000)
        var pacing = RatingPromptPacing()
        pacing.recordWatching(30 * minute)
        pacing.requested(version: "1.2", at: asked)
        #expect(!pacing.isRequestDue(version: "1.2", now: asked + 30 * day))
        pacing.recordWatching(2 * hour)
        #expect(!pacing.isRequestDue(version: "1.2", now: asked + 6 * day))
        #expect(pacing.isRequestDue(version: "1.2", now: asked + 7 * day))

        let followedUp = asked + 7 * day
        pacing.requested(version: "1.2", at: followedUp)
        pacing.recordWatching(48 * hour)
        #expect(!pacing.isRequestDue(version: "1.2", now: followedUp + 200 * day))
        #expect(!pacing.isRequestDue(version: "1.3", now: followedUp + 119 * day))
        #expect(pacing.isRequestDue(version: "1.3", now: followedUp + 120 * day))
    }

    @Test("Pacing saved by earlier versions: never asked is due, asked once gets the follow-up")
    func readsEarlierPacing() throws {
        let neverAsked = try JSONDecoder().decode(RatingPromptPacing.self, from: Data(#"{"watched":10800}"#.utf8))
        #expect(neverAsked.isRequestDue(version: "1.11.3"))

        let saved = Data(#"{"watched":10800,"watchedAtLastRequest":10800,"lastRequestedVersion":"1.11.2","lastRequestedAt":0}"#.utf8)
        var askedOnce = try JSONDecoder().decode(RatingPromptPacing.self, from: saved)
        let asked = Date(timeIntervalSinceReferenceDate: 0)
        askedOnce.recordWatching(2 * hour)
        #expect(!askedOnce.isRequestDue(version: "1.11.3", now: asked + 6 * day))
        #expect(askedOnce.isRequestDue(version: "1.11.3", now: asked + 7 * day))
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
