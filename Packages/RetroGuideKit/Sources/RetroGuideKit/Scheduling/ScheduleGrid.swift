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
        case .continuous: String(localized: "Back to back", bundle: .module, comment: "Schedule grid option: programs start right after each other, with no alignment.")
        case .fiveMinutes: String(localized: "5 minutes", bundle: .module)
        case .quarterHour: String(localized: "15 minutes", bundle: .module)
        case .halfHour: String(localized: "30 minutes", bundle: .module)
        }
    }

    /// The slot length a program of `duration` occupies on this grid.
    func slotLength(for duration: TimeInterval) -> TimeInterval {
        guard interval > .zero else { return duration }
        return (duration / interval).rounded(.up) * interval
    }
}
