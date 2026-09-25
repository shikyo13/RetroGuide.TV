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

    static func day(_ date: Date) -> String {
        dayAndDate.string(from: date)
    }

    static func duration(_ interval: TimeInterval) -> String {
        duration.string(from: max(interval, ScheduleConstants.secondsPerMinute)) ?? ""
    }

    static func remaining(in program: ScheduledProgram, at date: Date) -> String {
        "\(duration(program.contentEnd.timeIntervalSince(date))) left"
    }

    static func relativeDate(_ date: Date) -> String {
        relative.localizedString(for: date, relativeTo: .now)
    }

    static func hours(_ interval: TimeInterval) -> String {
        let hours = Int(interval / ScheduleConstants.secondsPerHour)
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }
}
