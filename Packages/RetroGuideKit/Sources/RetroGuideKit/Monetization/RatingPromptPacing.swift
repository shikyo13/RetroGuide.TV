import Foundation

/// When to ask for an App Store rating.
///
/// - First request: after half an hour of watching, or on the second local
///   calendar day of watching, whichever comes first.
/// - One follow-up: a week later, after some more watching. The system shows
///   it only to people who haven't rated (it checks for earlier feedback and
///   shows the request at most three times a year).
/// - After that: rarely (more viewing time, a new version and a long cooldown).
public struct RatingPromptPacing: Codable, Sendable, Hashable {
    /// Watching time before the first request.
    public static let firstRequestAfter: TimeInterval = 30 * ScheduleConstants.secondsPerMinute
    /// Calendar time between the first request and the follow-up. Apple's
    /// guidelines suggest at least a week or two between requests.
    public static let daysBeforeFollowUp = 7
    /// Watching time between the first request and the follow-up.
    public static let watchingBeforeFollowUp: TimeInterval = 2 * ScheduleConstants.secondsPerHour
    /// Watching time between later requests.
    public static let requestInterval: TimeInterval = 48 * ScheduleConstants.secondsPerHour
    /// Calendar time between later requests.
    public static let minimumDaysBetweenRequests = 120
    private static let secondsPerDay: TimeInterval = 24 * ScheduleConstants.secondsPerHour

    public private(set) var watched: TimeInterval
    /// `watched` when the rating was last requested.
    public private(set) var watchedAtLastRequest: TimeInterval?
    public private(set) var lastRequestedVersion: String?
    /// When the rating was last requested (`nil` in pacing saved before 1.9).
    public private(set) var lastRequestedAt: Date?
    private var firstViewingDate: Date?
    private var qualifiedOnLaterDay: Bool?
    /// Requests made so far (`nil` in pacing saved before the follow-up existed).
    private var requestCount: Int?

    public init(watched: TimeInterval = .zero, watchedAtLastRequest: TimeInterval? = nil, lastRequestedVersion: String? = nil, lastRequestedAt: Date? = nil) {
        self.watched = max(watched, .zero)
        self.watchedAtLastRequest = watchedAtLastRequest
        self.lastRequestedVersion = lastRequestedVersion
        self.lastRequestedAt = lastRequestedAt
    }

    public func isRequestDue(version: String, now: Date = .now) -> Bool {
        guard let watchedAtLastRequest else { return firstRequestIsDue }
        let watchedSince = watched - watchedAtLastRequest
        if isFollowUpNext {
            return hasPassed(days: Self.daysBeforeFollowUp, by: now) && watchedSince >= Self.watchingBeforeFollowUp
        }
        guard lastRequestedVersion != version else { return false }
        return hasPassed(days: Self.minimumDaysBetweenRequests, by: now) && watchedSince >= Self.requestInterval
    }

    /// Only the first request has been made. Pacing saved before requests
    /// were counted is treated the same way.
    private var isFollowUpNext: Bool {
        (requestCount ?? 1) == 1
    }

    /// Whether that many days have gone by since the last request (true when its date was never saved).
    private func hasPassed(days: Int, by now: Date) -> Bool {
        guard let lastRequestedAt else { return true }
        return now.timeIntervalSince(lastRequestedAt) >= TimeInterval(days) * Self.secondsPerDay
    }

    private var firstRequestIsDue: Bool {
        qualifiedOnLaterDay == true || watched >= Self.firstRequestAfter
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
        requestCount = watchedAtLastRequest == nil ? 1 : (requestCount ?? 1) + 1
        watchedAtLastRequest = watched
        lastRequestedVersion = version
        lastRequestedAt = date
    }
}
