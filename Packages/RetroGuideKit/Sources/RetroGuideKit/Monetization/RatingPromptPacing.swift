import Foundation

/// The first rating request follows playback on two local calendar days.
/// Later requests require more viewing time, a new version and a cooldown.
public struct RatingPromptPacing: Codable, Sendable, Hashable {
    /// First-request threshold for saved pacing that predates viewing days.
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
    private var firstViewingDate: Date?
    private var qualifiedOnLaterDay: Bool?

    public init(watched: TimeInterval = .zero, watchedAtLastRequest: TimeInterval? = nil, lastRequestedVersion: String? = nil, lastRequestedAt: Date? = nil) {
        self.watched = max(watched, .zero)
        self.watchedAtLastRequest = watchedAtLastRequest
        self.lastRequestedVersion = lastRequestedVersion
        self.lastRequestedAt = lastRequestedAt
    }

    public func isRequestDue(version: String, now: Date = .now) -> Bool {
        guard lastRequestedVersion != version else { return false }
        guard let watchedAtLastRequest else { return firstRequestIsDue }
        let interval = TimeInterval(Self.minimumDaysBetweenRequests) * 86_400
        if let lastRequestedAt, now.timeIntervalSince(lastRequestedAt) < interval { return false }
        return watched - watchedAtLastRequest >= Self.requestInterval
    }

    private var firstRequestIsDue: Bool {
        qualifiedOnLaterDay == true || (firstViewingDate == nil && watched >= Self.firstRequestAfter)
    }

    public mutating func recordWatching(_ duration: TimeInterval, at date: Date = .now, calendar: Calendar = .autoupdatingCurrent) {
        guard duration > .zero else { return }
        if watchedAtLastRequest == nil && !firstRequestIsDue {
            if let firstViewingDate {
                if calendar.compare(date, to: firstViewingDate, toGranularity: .day) == .orderedDescending {
                    qualifiedOnLaterDay = true
                }
            } else {
                firstViewingDate = date
            }
        }
        watched += duration
    }

    public mutating func requested(version: String, at date: Date = .now) {
        watchedAtLastRequest = watched
        lastRequestedVersion = version
        lastRequestedAt = date
    }
}
