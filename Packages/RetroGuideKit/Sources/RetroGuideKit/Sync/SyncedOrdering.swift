import Foundation

/// Schedule orders as synced settings store them.
///
/// Versions before Release Order (1.8) fail to read a whole settings
/// snapshot that names an order they don't know. Release Order is therefore
/// written as Marathon plus a separate flag that they ignore: they read
/// every setting and show Marathon. Orders this version doesn't know are
/// skipped rather than failing everything.
enum SyncedOrdering {
    static let releaseFlag = "release"

    /// The order older versions can read, and the flag for one they can't.
    static func stored(_ ordering: ScheduleOrdering) -> (legacy: ScheduleOrdering, flag: String?) {
        ordering == .releaseOrder ? (.marathon, releaseFlag) : (ordering, nil)
    }

    /// The order a stored value and flag describe. A flag only counts on
    /// Marathon, so an older version choosing another order wins.
    static func read(_ raw: String?, flag: String?) -> ScheduleOrdering? {
        guard let ordering = raw.flatMap(ScheduleOrdering.init(rawValue:)) else { return nil }
        return ordering == .marathon && flag == releaseFlag ? .releaseOrder : ordering
    }
}
