import Foundation
import RetroGuideKit

/// Cached formatters for times, ranges and durations shown in the guide and banners.
@MainActor
enum ScheduleFormatting {
    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static let dayAndDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMd")
        return formatter
    }()

    private static let duration: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }()

    /// Whole hours spelled out: "1 hour", "12 hours".
    private static let wholeHours: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour]
        formatter.unitsStyle = .full
        return formatter
    }()

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    static func time(_ date: Date) -> String {
        time.string(from: date)
    }

    static func range(_ program: ScheduledProgram) -> String {
        "\(time(program.start)) – \(time(program.slotEnd))"
    }

    /// "3:30 PM", "Tomorrow 9:00 AM" or "Sat, Sep 27 9:00 AM".
    static func dayAndTime(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return time(date) }
        if calendar.isDateInTomorrow(date) { return String(localized: "Tomorrow \(time(date))") }
        return String(localized: "\(dayAndDate.string(from: date)) \(time(date))", comment: "A day and date, then a time: “Sat, Sep 27 9:00 AM”")
    }

    static func day(_ date: Date) -> String {
        dayAndDate.string(from: date)
    }

    static func duration(_ interval: TimeInterval) -> String {
        duration.string(from: max(interval, ScheduleConstants.secondsPerMinute)) ?? ""
    }

    static func remaining(in program: ScheduledProgram, at date: Date) -> String {
        String(localized: "\(duration(program.contentEnd.timeIntervalSince(date))) left", comment: "Time left in a program: “25m left”")
    }

    static func relativeDate(_ date: Date) -> String {
        relative.localizedString(for: date, relativeTo: .now)
    }

    static func hours(_ interval: TimeInterval) -> String {
        let hours = (interval / ScheduleConstants.secondsPerHour).rounded(.towardZero)
        return wholeHours.string(from: hours * ScheduleConstants.secondsPerHour) ?? ""
    }
}
