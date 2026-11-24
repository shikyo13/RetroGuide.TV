import Foundation

/// Today's playing time, for ``UsageEvent/Name/watchTime``: each threshold is
/// reported the first time the day's total reaches it. A new UTC day starts at zero.
public struct WatchTimeTally: Codable, Equatable, Sendable {
    public private(set) var day: String
    public private(set) var seconds: Double

    public init(day: String = "", seconds: Double = .zero) {
        self.day = day
        self.seconds = seconds
    }

    /// Adds `seconds` of playing to the day of `date`, returning the thresholds crossed.
    public mutating func add(_ added: Double, at date: Date) -> [UsageEvent.WatchTime] {
        let today = UsageEvent.day(of: date)
        if today != day {
            day = today
            seconds = .zero
        }
        let before = seconds
        seconds += max(.zero, added)
        return UsageEvent.WatchTime.allCases.filter { before < $0.seconds && seconds >= $0.seconds }
    }
}
