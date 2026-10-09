import Foundation

/// What a channel's schedule is built from: its items grouped into shows and
/// how long each one's slot is.
final class ScheduleContext: Sendable {
    let channelID: String
    let items: [MediaItem]
    /// Every item's slot, in whole milliseconds, so schedules computed in
    /// different ways add up to exactly the same times.
    let slotLengths: [Int]
    /// Each show's (or movie's) item indices in broadcast order, specials last.
    let shows: [[Int]]
    /// Id of every show (series id, or the movie's own id).
    let showIDs: [String]
    /// Show index of every item.
    let showOfItem: [Int]
    let seed: UInt64

    init(channelID: String, items: [MediaItem], grid: ScheduleGrid) {
        self.channelID = channelID
        self.items = items
        self.slotLengths = items.map { ScheduleTime.milliseconds(max(grid.slotLength(for: $0.duration), ScheduleConstants.minimumProgramDuration)) }
        var groups: [String: [Int]] = [:]
        for index in items.indices where items[index].duration > .zero {
            groups[items[index].showID, default: []].append(index)
        }
        let sorted = groups.sorted { $0.key < $1.key }
        self.showIDs = sorted.map(\.key)
        self.shows = sorted.map { _, indices in
            indices.sorted { lhs, rhs in
                let left = items[lhs].series?.broadcastOrder ?? (.zero, .zero)
                let right = items[rhs].series?.broadcastOrder ?? (.zero, .zero)
                return left != right ? left < right : items[lhs].id < items[rhs].id
            }
        }
        var showOfItem = Array(repeating: 0, count: items.count)
        for (show, indices) in shows.enumerated() {
            for index in indices {
                showOfItem[index] = show
            }
        }
        self.showOfItem = showOfItem
        self.seed = StableHash.fnv1a(channelID)
    }

    var isEmpty: Bool {
        shows.isEmpty
    }

    /// The episode `show` starts from at the epoch: a different one on every
    /// channel, so channels sharing a show don't move through it in step and
    /// air the same episode at the same time.
    func firstEpisode(of show: Int) -> Int {
        Int((StableHash.fnv1a(showIDs[show]) ^ seed) % UInt64(shows[show].count))
    }

    /// The program airing `item` from `start` (milliseconds since the epoch).
    func program(item: Int, start: Int, cycle: Int, slot: Int) -> ScheduledProgram {
        let media = items[item]
        let begins = ScheduleTime.date(start)
        return ScheduledProgram(
            channelID: channelID,
            item: media,
            start: begins,
            contentEnd: begins.addingTimeInterval(media.duration),
            slotEnd: ScheduleTime.date(start + slotLengths[item]),
            cycle: cycle,
            slot: slot
        )
    }
}

/// Schedule times as whole milliseconds since ``ScheduleConstants/epoch``.
enum ScheduleTime {
    static let perSecond = 1_000
    static let perDay = 24 * 60 * 60 * perSecond

    static func milliseconds(_ seconds: TimeInterval) -> Int {
        Int((seconds * Double(perSecond)).rounded())
    }

    static func milliseconds(since date: Date) -> Int {
        Int((date.timeIntervalSince(ScheduleConstants.epoch) * Double(perSecond)).rounded())
    }

    static func seconds(_ milliseconds: Int) -> TimeInterval {
        TimeInterval(milliseconds) / Double(perSecond)
    }

    static func date(_ milliseconds: Int) -> Date {
        ScheduleConstants.epoch.addingTimeInterval(seconds(milliseconds))
    }
}
