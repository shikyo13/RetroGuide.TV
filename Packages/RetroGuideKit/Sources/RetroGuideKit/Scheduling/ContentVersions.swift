import Foundation

/// When new library content joins the schedules.
///
/// An item becomes part of its channels at the first broadcast-day boundary
/// (09:00 UTC, about 4–5 am in the US) at least an hour after it was added
/// to its server. Every device derives that moment from the server's own
/// date, so they agree no matter when each one refreshed, and nothing
/// already scheduled before the boundary ever changes when content arrives.
enum ContentVersions {
    enum Tuning {
        /// Broadcast days start at 09:00 UTC.
        static let dayStart = 9 * 60 * 60 * ScheduleTime.perSecond
        /// An item must be on its server this long before the boundary it joins at.
        static let lead = 60 * 60 * ScheduleTime.perSecond
        /// Dates further ahead than this are bad metadata (Plex has been seen
        /// reporting 2145): such items count as always there.
        static let futureTolerance: TimeInterval = 24 * ScheduleConstants.secondsPerHour
    }

    /// Milliseconds after the epoch when an item added at `addedAt` joins
    /// the schedule; zero for items without a believable date or added
    /// before the epoch.
    static func effectiveTime(addedAt: Date?, now: Date = .now) -> Int {
        guard let addedAt, addedAt.timeIntervalSince(now) <= Tuning.futureTolerance else { return .zero }
        let ready = ScheduleTime.milliseconds(since: addedAt) + Tuning.lead
        guard ready > Tuning.dayStart else { return .zero }
        let days = (ready - Tuning.dayStart + ScheduleTime.perDay - 1) / ScheduleTime.perDay
        return Tuning.dayStart + days * ScheduleTime.perDay
    }
}
