import Foundation

/// Schedule orders as synced settings store them.
///
/// Versions before Release Order (1.8) fail to read a whole settings
/// snapshot that names an order they don't know. Each order is therefore
/// written twice: as an order they know (Release Order as Marathon), and as
/// the full order in a separate record they ignore. The full order counts
/// only while it agrees with the one older versions see, so an older device
/// choosing a different order wins. Both records change together on every
/// edit, so the newest edit wins on every device.
enum SyncedOrdering {
    /// Written by early 1.9 test builds for Release Order.
    private static let earlyReleaseFlag = "release"

    /// The order older versions can read, and the full order.
    static func stored(_ ordering: ScheduleOrdering) -> (legacy: ScheduleOrdering, full: String) {
        (ordering == .releaseOrder ? .marathon : ordering, ordering.rawValue)
    }

    /// The order a stored value and its full order describe.
    static func read(_ raw: String?, full: String?) -> ScheduleOrdering? {
        guard let legacy = raw.flatMap(ScheduleOrdering.init(rawValue:)) else { return nil }
        let complete = full == earlyReleaseFlag ? .releaseOrder : full.flatMap(ScheduleOrdering.init(rawValue:))
        guard let complete, stored(complete).legacy == legacy else { return legacy }
        return complete
    }
}
