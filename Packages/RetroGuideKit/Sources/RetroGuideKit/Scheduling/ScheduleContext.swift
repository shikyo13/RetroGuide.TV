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
    /// When each item joins the schedule (``ContentVersions``), in
    /// milliseconds after the epoch; zero for items that always have.
    let effective: [Int]
    /// Every distinct moment the channel's content changes, ascending.
    let versionTimes: [Int]
    /// Each show's shortest slot (a lower bound for any subset of its episodes).
    let shortestSlot: [Int]
    let seed: UInt64
    /// Each show's stable rank per salt ("" and each shuffled round), worked out once.
    private let ranks: [String: [UInt64]]

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
        let effective = items.map { ContentVersions.effectiveTime(addedAt: $0.addedAt) }
        self.effective = effective
        self.versionTimes = Set(shows.joined().map { effective[$0] }).sorted()
        let slotLengths = self.slotLengths
        self.shortestSlot = shows.map { $0.map { slotLengths[$0] }.min() ?? .zero }
        let seed = StableHash.fnv1a(channelID)
        self.seed = seed
        let ids = showIDs
        let salts = [""] + (0..<CycleSegment.Tuning.shuffledRounds).map { "round\($0)" }
        self.ranks = Dictionary(uniqueKeysWithValues: salts.map { salt in
            (salt, ids.map { StableHash.fnv1a("\(seed)/\(salt)/\($0)") })
        })
    }

    var isEmpty: Bool {
        shows.isEmpty
    }

    /// The episode `show` starts from when it first comes on (of its
    /// `count` episodes then): a different one on every channel, so channels
    /// sharing a show don't move through it in step and air the same episode
    /// at the same time.
    func firstEpisode(of show: Int, count: Int) -> Int {
        Int((StableHash.fnv1a(showIDs[show]) ^ seed) % UInt64(max(count, 1)))
    }

    /// A stable rank for `show` on this channel, so the order of shows
    /// depends on which shows there are, never on their positions in a list:
    /// a show joining or leaving moves nobody else.
    /// Every show's rank for `salt`, to sort by without looking it up per comparison.
    func ranks(salt: String = "") -> [UInt64] {
        ranks[salt] ?? showIDs.map { StableHash.fnv1a("\(seed)/\(salt)/\($0)") }
    }

    func rank(of show: Int, salt: String = "") -> UInt64 {
        ranks[salt]?[show] ?? StableHash.fnv1a("\(seed)/\(salt)/\(showIDs[show])")
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
