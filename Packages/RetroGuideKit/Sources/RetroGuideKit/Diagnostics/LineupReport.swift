import Foundation

/// Scores a lineup against the goals channel generation is designed for:
/// every title has a themed home, titles don't repeat across many channels,
/// channels are distinct, episodes don't come round again too soon, and each
/// channel shows a real mix of programs every day.
public struct LineupReport: Sendable, CustomStringConvertible {
    public enum Tuning {
        /// Channels sharing this much of their combined titles count as duplicates.
        public static let duplicateSimilarity = LineupOptions.Defaults.nearDuplicateSimilarity
        /// How far ahead to look for an episode coming round again.
        public static let repeatHorizon: TimeInterval = 30 * 24 * ScheduleConstants.secondsPerHour
        /// Length of the window used for "different programs per day".
        public static let dayLength: TimeInterval = 24 * ScheduleConstants.secondsPerHour
        /// A channel should last this long before repeating…
        public static let expectedRepeatDays = 7.0
        /// …or use at least this share of its content first.
        public static let contentUse = 0.9
        /// A channel should air this many different programs a day (or all it has).
        public static let expectedProgramsPerDay = 4
        /// Channels with less content than this repeat within a day whatever
        /// the schedule does, so they aren't held to the repeat goal.
        public static let repeatCheckMinimumContent: TimeInterval = 24 * ScheduleConstants.secondsPerHour
        /// A channel airing this share of every show or every movie is a catch-all.
        public static let catchAllShare = 0.9
        /// How long to check for the same show on several channels at once.
        public static let simulcastWindow: TimeInterval = 7 * 24 * ScheduleConstants.secondsPerHour
        /// Fixed reference point so reports are comparable between runs.
        public static let referenceDate = ScheduleConstants.epoch.addingTimeInterval(1_000 * 24 * ScheduleConstants.secondsPerHour)
    }

    public let channelCount: Int
    public let channelsBySource: [ChannelSource: Int]
    public let titleCount: Int
    /// Titles (shows and movies) without any themed channel.
    public let uncoveredTitles: [String]
    public let themedChannelsPerTitleMedian: Int
    public let themedChannelsPerTitleMax: Int
    public let duplicateChannelPairs: Int
    /// Days until any episode on a channel airs again, across themed channels (capped at the horizon).
    public let repeatDaysLowest: Double
    public let repeatDaysMedian: Double
    /// Channels repeating before a week while they still had content left, and
    /// channels airing fewer different programs a day than they could.
    public let repeatShortfalls: [String]
    public let varietyShortfalls: [String]
    /// The channel that repeats soonest, and the one with the least variety.
    public let soonestRepeatingChannel: String
    public let leastVariedChannel: String
    /// Different shows or movies airing on a themed channel in one day.
    public let programsPerDayLowest: Int
    public let programsPerDayMedian: Int
    public let deadAirShare: Double
    /// Most channels (24/7 and custom aside) airing one show at the same moment,
    /// and the share of sampled moments where some show was over the limit.
    public let simulcastMax: Int
    public let simulcastOverLimitShare: Double
    /// Share of sampled moments where one episode or movie was on two
    /// channels at once (every visible channel, 24/7 and custom included).
    public let sameEpisodeShare: Double
    /// Items stored across all channels per library item (memory proxy).
    public let storageFactor: Double

    public init(lineup: [Channel], index: LibraryIndex, simulcastLimit: SimulcastLimit = .two) {
        let visible = lineup.filter { !$0.isHidden }
        let library = TitleCounts(index.items.filter(Self.isSchedulable))
        let themed = visible.filter { Self.role(of: $0, library: library) == .themed }
        channelCount = visible.count
        channelsBySource = Dictionary(grouping: visible, by: \.definition.source).mapValues(\.count)

        let allTitles = Set(index.items.filter(Self.isSchedulable).map(Self.title))
        titleCount = allTitles.count
        var perTitle: [String: Int] = [:]
        for channel in themed {
            for title in Set(channel.items.map(Self.title)) {
                perTitle[title, default: 0] += 1
            }
        }
        // In libraries too small for themed channels of a kind, the catch-alls are home.
        let themedKinds = Set(themed.flatMap { $0.items.map { $0.series != nil } })
        let showTitles = Set(index.items.filter { $0.series != nil }.map(\.showID))
        uncoveredTitles = allTitles.filter { perTitle[$0] == nil && themedKinds.contains(showTitles.contains($0)) }.sorted()
        let counts = allTitles.map { perTitle[$0, default: 0] }.sorted()
        themedChannelsPerTitleMedian = counts.isEmpty ? 0 : counts[counts.count / 2]
        themedChannelsPerTitleMax = counts.last ?? 0

        let titleSets = themed.map { Set($0.items.map(Self.title)) }
        var duplicates = 0
        for first in titleSets.indices {
            for second in titleSets.indices where second > first {
                let union = titleSets[first].union(titleSets[second]).count
                if union > 0, Double(titleSets[first].intersection(titleSets[second]).count) / Double(union) >= Tuning.duplicateSimilarity {
                    duplicates += 1
                }
            }
        }
        duplicateChannelPairs = duplicates

        let repeats = themed.map { ($0, Self.repeatDays(of: $0)) }.sorted { $0.1 < $1.1 }
        let repeatDays = repeats.map(\.1)
        repeatDaysLowest = repeatDays.first ?? 0
        repeatDaysMedian = repeatDays.isEmpty ? 0 : repeatDays[repeatDays.count / 2]
        soonestRepeatingChannel = repeats.first.map { Self.label($0.0) } ?? "-"
        repeatShortfalls = repeats.filter { channel, days in
            guard channel.totalRuntime >= Tuning.repeatCheckMinimumContent else { return false }
            let contentDays = channel.totalRuntime / Tuning.dayLength
            return days < min(Tuning.expectedRepeatDays, contentDays * Tuning.contentUse)
        }.map { Self.label($0.0) }

        let day = DateInterval(start: Tuning.referenceDate, duration: Tuning.dayLength)
        var perDay: [Int] = []
        var dead: TimeInterval = 0
        var scheduled: TimeInterval = 0
        var leastVaried: (channel: Channel, count: Int)?
        var varietyGaps: [String] = []
        for channel in themed {
            let programs = channel.timeline.programs(overlapping: day)
            let count = Set(programs.map { Self.title(of: $0.item) }).count
            perDay.append(count)
            if leastVaried.map({ count < $0.count }) ?? true {
                leastVaried = (channel, count)
            }
            if count < min(Tuning.expectedProgramsPerDay, Set(channel.items.map(Self.title)).count) {
                varietyGaps.append(Self.label(channel))
            }
            for program in programs {
                dead += program.slotEnd.timeIntervalSince(program.contentEnd)
                scheduled += program.slotEnd.timeIntervalSince(program.start)
            }
        }
        perDay.sort()
        leastVariedChannel = leastVaried.map { Self.label($0.channel) } ?? "-"
        varietyShortfalls = varietyGaps
        programsPerDayLowest = perDay.first ?? 0
        programsPerDayMedian = perDay.isEmpty ? 0 : perDay[perDay.count / 2]
        deadAirShare = scheduled > 0 ? dead / scheduled : 0
        let simulcast = Self.overlap(on: visible.filter { ![.series, .custom].contains($0.definition.source) }, of: Self.title, limit: simulcastLimit.channels)
        simulcastMax = simulcast.max
        simulcastOverLimitShare = simulcast.overLimitShare
        sameEpisodeShare = Self.overlap(on: visible, of: \.id, limit: 1).overLimitShare
        storageFactor = index.items.isEmpty ? 0 : Double(visible.reduce(0) { $0 + $1.items.count }) / Double(index.items.count)
    }

    public var description: String {
        let sources = channelsBySource.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue)=\($0.value)" }.joined(separator: " ")
        return """
        channels \(channelCount) [\(sources)]
        titles \(titleCount), without a themed home \(uncoveredTitles.count)
        themed channels per title: median \(themedChannelsPerTitleMedian), max \(themedChannelsPerTitleMax)
        near-duplicate channel pairs \(duplicateChannelPairs)
        days before an episode repeats: lowest \(String(format: "%.1f", repeatDaysLowest)) (\(soonestRepeatingChannel)), median \(String(format: "%.1f", repeatDaysMedian))
        channels repeating early \(repeatShortfalls.count), lacking variety \(varietyShortfalls.count)
        different programs per channel per day: lowest \(programsPerDayLowest) (\(leastVariedChannel)), median \(programsPerDayMedian)
        same show at once: max \(simulcastMax) channels, over the limit \(String(format: "%.1f", simulcastOverLimitShare * 100))% of the time
        same episode at once \(String(format: "%.1f", sameEpisodeShare * 100))% of the time
        dead air \(String(format: "%.1f", deadAirShare * 100))%, stored items per library item \(String(format: "%.1f", storageFactor))
        """
    }

    // MARK: - Roles

    enum Role {
        case catchAll
        case marathon
        case custom
        case themed
    }

    struct TitleCounts {
        let shows: Int
        let movies: Int

        init(_ items: [MediaItem]) {
            shows = Set(items.filter { $0.series != nil }.map(\.showID)).count
            movies = items.filter { $0.series == nil }.count
        }
    }

    /// Same classification as lineup generation: channels covering (nearly) every
    /// show or every movie are catch-alls; 24/7 and custom channels are their own thing.
    static func role(of channel: Channel, library: TitleCounts) -> Role {
        switch channel.definition.source {
        case .series: return .marathon
        case .custom: return .custom
        default: break
        }
        let own = TitleCounts(channel.items)
        let share = Tuning.catchAllShare
        let coversShows = own.shows > 0 && Double(own.shows) >= share * Double(library.shows)
        let coversMovies = own.movies > 0 && Double(own.movies) >= share * Double(library.movies)
        let isCatchAll = (own.movies == 0 && coversShows) || (own.shows == 0 && coversMovies) || (coversShows && coversMovies)
        return isCatchAll ? .catchAll : .themed
    }

    // MARK: - Measurements

    /// Walks the schedule until some episode airs a second time.
    private static func repeatDays(of channel: Channel) -> Double {
        guard var program = channel.timeline.program(at: Tuning.referenceDate) else { return 0 }
        var seen: Set<String> = []
        let horizon = Tuning.referenceDate.addingTimeInterval(Tuning.repeatHorizon)
        while program.start < horizon {
            if !seen.insert(program.item.id).inserted {
                return program.start.timeIntervalSince(Tuning.referenceDate) / Tuning.dayLength
            }
            guard let next = channel.timeline.program(after: program) else { break }
            program = next
        }
        return Tuning.repeatHorizon / Tuning.dayLength
    }

    /// Sweeps every program in the week after the reference date for titles
    /// (shows, or single episodes and movies, by `key`) airing on several
    /// channels at once.
    private static func overlap(on channels: [Channel], of key: (MediaItem) -> String, limit: Int?) -> (max: Int, overLimitShare: Double) {
        let window = DateInterval(start: Tuning.referenceDate, duration: Tuning.simulcastWindow)
        var events: [(time: Date, change: Int, show: String)] = []
        for channel in channels {
            for program in channel.timeline.programs(overlapping: window) {
                let show = key(program.item)
                events.append((max(program.start, window.start), 1, show))
                events.append((min(program.slotEnd, window.end), -1, show))
            }
        }
        // Ends before starts at the same instant: back-to-back isn't overlap.
        events.sort { ($0.time, $0.change) < ($1.time, $1.change) }
        var airing: [String: Int] = [:]
        var overCount = 0
        var overSince: Date?
        var overTime: TimeInterval = .zero
        var highest = 0
        for event in events {
            let before = airing[event.show, default: 0]
            let after = before + event.change
            airing[event.show] = after
            highest = max(highest, after)
            guard let limit else { continue }
            if before <= limit, after > limit {
                if overCount == 0 { overSince = event.time }
                overCount += 1
            } else if before > limit, after <= limit {
                overCount -= 1
                if overCount == 0, let since = overSince {
                    overTime += event.time.timeIntervalSince(since)
                }
            }
        }
        return (highest, overTime / window.duration)
    }

    private static func label(_ channel: Channel) -> String {
        let titles = Set(channel.items.map(title)).count
        let scheduler = channel.timeline is ChannelTimeline ? "cycle" : "simulated"
        return "\(channel.number) \(channel.name), \(titles) titles, \(Int(channel.totalRuntime / ScheduleConstants.secondsPerHour)) h, \(channel.definition.ordering.rawValue) \(scheduler)"
    }

    private static func isSchedulable(_ item: MediaItem) -> Bool {
        item.duration >= ScheduleConstants.minimumProgramDuration
    }

    static func title(of item: MediaItem) -> String {
        item.showID
    }
}
