import Foundation

/// Paces asking for an App Store rating: first after a few hours of
/// watching, then again only after a long stretch more, and at most once per
/// app version. Counted in time actually spent watching, like ``AdPacing``.
/// (The system also caps the prompt at three times a year.)
public struct RatingPromptPacing: Codable, Sendable, Hashable {
    /// Watching time before the first request.
    public static let firstRequestAfter: TimeInterval = 3 * ScheduleConstants.secondsPerHour
    /// Watching time between later requests.
    public static let requestInterval: TimeInterval = 48 * ScheduleConstants.secondsPerHour

    public private(set) var watched: TimeInterval
    /// `watched` when the rating was last requested.
    public private(set) var watchedAtLastRequest: TimeInterval?
    public private(set) var lastRequestedVersion: String?

    public init(watched: TimeInterval = .zero, watchedAtLastRequest: TimeInterval? = nil, lastRequestedVersion: String? = nil) {
        self.watched = max(watched, .zero)
        self.watchedAtLastRequest = watchedAtLastRequest
        self.lastRequestedVersion = lastRequestedVersion
    }

    public func isRequestDue(version: String) -> Bool {
        guard lastRequestedVersion != version else { return false }
        guard let watchedAtLastRequest else { return watched >= Self.firstRequestAfter }
        return watched - watchedAtLastRequest >= Self.requestInterval
    }

    public mutating func recordWatching(_ duration: TimeInterval) {
        guard duration > .zero else { return }
        watched += duration
    }

    public mutating func requested(version: String) {
        watchedAtLastRequest = watched
        lastRequestedVersion = version
    }
}
