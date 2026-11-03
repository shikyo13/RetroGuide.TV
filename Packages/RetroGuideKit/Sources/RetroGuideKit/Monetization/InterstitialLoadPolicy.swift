import Foundation

/// Freshness and bounded retry timing for a single preloaded full-screen ad.
public struct InterstitialLoadPolicy: Sendable {
    /// Refresh before the SDK's one-hour expiration, including the maintenance interval.
    public static let maximumAge: TimeInterval = 55 * ScheduleConstants.secondsPerMinute
    public static let maintenanceInterval: TimeInterval = ScheduleConstants.secondsPerMinute
    public static let maximumRetryDelay: TimeInterval = 15 * ScheduleConstants.secondsPerMinute

    private var loadedAt: Date?
    private var retryAfter: Date?
    private var retryDelay = maintenanceInterval

    public init() {}

    public func isFresh(at now: Date) -> Bool {
        guard let loadedAt else { return false }
        let age = now.timeIntervalSince(loadedAt)
        return age >= .zero && age < Self.maximumAge
    }

    public func shouldLoad(at now: Date) -> Bool {
        !isFresh(at: now) && (retryAfter.map { now >= $0 } ?? true)
    }

    public mutating func loaded(at now: Date) {
        loadedAt = now
        retryAfter = nil
        retryDelay = Self.maintenanceInterval
    }

    public mutating func failed(at now: Date) {
        loadedAt = nil
        retryAfter = now.addingTimeInterval(retryDelay)
        retryDelay = min(retryDelay * 2, Self.maximumRetryDelay)
    }

    public mutating func discard() {
        loadedAt = nil
    }
}
