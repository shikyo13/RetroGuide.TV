import Foundation

/// The order of a ``ScheduleOrdering/releaseOrder`` channel: every movie and
/// episode by the date it came out, oldest first, so a film series plays in
/// order and several shows interleave as they first aired.
///
/// A show's own episodes always keep their broadcast order: an episode with
/// a missing or out-of-order date airs after the one before it. Titles with
/// no date or year at all come last, by title.
enum ReleaseSequence {
    /// `indices` of `items` in release order.
    static func order(_ indices: [Int], of items: [MediaItem]) -> [Int] {
        var byShow: [String: [Int]] = [:]
        for index in indices {
            byShow[items[index].showID, default: []].append(index)
        }
        var keyed: [(date: Date?, title: String, show: String, position: Int, item: Int)] = []
        keyed.reserveCapacity(indices.count)
        for (show, members) in byShow {
            let episodes = members.sorted { lhs, rhs in
                let left = items[lhs].series?.broadcastOrder ?? (.zero, .zero)
                let right = items[rhs].series?.broadcastOrder ?? (.zero, .zero)
                return left != right ? left < right : items[lhs].id < items[rhs].id
            }
            // Never earlier than the episode before it, so merging by date keeps broadcast order.
            let dates = episodes.map { releaseDate(of: items[$0]) }
            var floor = dates.compactMap { $0 }.first
            for (position, item) in episodes.enumerated() {
                if let date = dates[position], floor.map({ date > $0 }) ?? true {
                    floor = date
                }
                keyed.append((floor, items[item].headline.localizedLowercase, show, position, item))
            }
        }
        keyed.sort { lhs, rhs in
            switch (lhs.date, rhs.date) {
            case let (left?, right?) where left != right: return left < right
            case (.some, .none): return true
            case (.none, .some): return false
            default: return (lhs.title, lhs.show, lhs.position) < (rhs.title, rhs.show, rhs.position)
            }
        }
        return keyed.map(\.item)
    }

    /// The item's release date, or January 1 of its year when only the year is known.
    static func releaseDate(of item: MediaItem) -> Date? {
        if let released = item.released { return released }
        guard let year = item.year else { return nil }
        return DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "UTC"), year: year, month: 1, day: 1).date
    }
}
