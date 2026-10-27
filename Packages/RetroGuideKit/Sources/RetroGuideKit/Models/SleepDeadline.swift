import Foundation

/// A session timer uses an absolute deadline so background suspension cannot extend it.
public enum SleepDeadline {
    public static let presets = [15, 30, 60, 90]
    public static let minute: TimeInterval = 60
    public static let customRange = 1...240

    public static func duration(minutes: Int, now: Date = .now) -> Date {
        now.addingTimeInterval(Double(min(max(minutes, customRange.lowerBound), customRange.upperBound)) * minute)
    }

    public static func endOfProgram(_ program: ScheduledProgram?, now: Date = .now) -> Date? {
        guard let program, program.contentEnd > now else { return nil }
        return program.contentEnd
    }
}
