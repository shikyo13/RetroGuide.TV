import Foundation

/// A fixed sequence inside one program's intermission, independent of playback attempts.
public struct CommercialBreakPlan: Sendable {
    public enum Limits {
        public static let maximumClips = 32
        public static let maximumCatalogItems = 2_000
        public static let minimumClipDuration: TimeInterval = 1
        public static let maximumClipDuration: TimeInterval = 5 * ScheduleConstants.secondsPerMinute
    }
    public struct Clip: Sendable {
        public let item: MediaItem
        public let start: Date
        public var end: Date { start.addingTimeInterval(item.duration) }
        public func position(at date: Date) -> TimeInterval { min(max(date.timeIntervalSince(start), .zero), item.duration) }
    }
    public let end: Date
    public let clips: [Clip]
    public func clip(at date: Date) -> Clip? { clips.first { date >= $0.start && date < $0.end } }
    public static func eligible(_ item: MediaItem) -> Bool {
        item.duration.isFinite && item.duration >= Limits.minimumClipDuration && item.duration <= Limits.maximumClipDuration
    }
    public init(program: ScheduledProgram) {
        end = program.slotEnd
        var cursor = program.contentEnd
        clips = program.commercials.filter(Self.eligible).map { item in
            defer { cursor.addTimeInterval(item.duration) }
            return Clip(item: item, start: cursor)
        }
    }
}
