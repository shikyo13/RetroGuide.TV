import Foundation

/// Paces asking for an App Store rating: first after a few hours of
/// watching, then again only after a long stretch more, a few months and a
/// new app version. Counted in time actually spent watching, like
/// ``AdPacing``. Nothing says whether someone already rated, so repeats are
/// rare. (The system also caps the prompt at three times a year.)
public struct RatingPromptPacing: Codable, Sendable, Hashable {
    /// Watching time before the first request.
    public static let firstRequestAfter: TimeInterval = 3 * ScheduleConstants.secondsPerHour
    /// Watching time between later requests.
    public static let requestInterval: TimeInterval = 48 * ScheduleConstants.secondsPerHour
    /// Calendar time between later requests.
    public static let minimumDaysBetweenRequests = 120

    public private(set) var watched: TimeInterval
    /// `watched` when the rating was last requested.
    public private(set) var watchedAtLastRequest: TimeInterval?
    public private(set) var lastRequestedVersion: String?
    /// When the rating was last requested (`nil` in pacing saved before 1.9).
    public private(set) var lastRequestedAt: Date?

    public init(watched: TimeInterval = .zero, watchedAtLastRequest: TimeInterval? = nil, lastRequestedVersion: String? = nil, lastRequestedAt: Date? = nil) {
        self.watched = max(watched, .zero)
        self.watchedAtLastRequest = watchedAtLastRequest
        self.lastRequestedVersion = lastRequestedVersion
        self.lastRequestedAt = lastRequestedAt
    }

    public func isRequestDue(version: String, now: Date = .now) -> Bool {
        guard lastRequestedVersion != version else { return false }
        guard let watchedAtLastRequest else { return watched >= Self.firstRequestAfter }
        let interval = TimeInterval(Self.minimumDaysBetweenRequests) * 86_400
        if let lastRequestedAt, now.timeIntervalSince(lastRequestedAt) < interval { return false }
        return watched - watchedAtLastRequest >= Self.requestInterval
    }

    public mutating func recordWatching(_ duration: TimeInterval) {
        guard duration > .zero else { return }
        watched += duration
    }

    public mutating func requested(version: String, at date: Date = .now) {
        watchedAtLastRequest = watched
        lastRequestedVersion = version
        lastRequestedAt = date
    }
}
