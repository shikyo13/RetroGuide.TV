import Foundation

/// Optional alignment of program start times to a broadcast-style grid.
///
/// With alignment on, each program's slot is rounded up to the next multiple of
/// the grid interval and the remainder airs as an intermission card, just like
/// the filler between shows on real TV.
public enum ScheduleGrid: Int, Codable, Sendable, CaseIterable, Hashable {
    case continuous = 0
    case fiveMinutes = 5
    case quarterHour = 15
    case halfHour = 30

    public var interval: TimeInterval {
        TimeInterval(rawValue) * ScheduleConstants.secondsPerMinute
    }

    public var displayName: String {
        switch self {
        case .continuous: "Back to back"
        case .fiveMinutes: "5 minutes"
        case .quarterHour: "15 minutes"
        case .halfHour: "30 minutes"
        }
    }

    /// The slot length a program of `duration` occupies on this grid.
    func slotLength(for duration: TimeInterval) -> TimeInterval {
        guard interval > .zero else { return duration }
        return (duration / interval).rounded(.up) * interval
    }
}
