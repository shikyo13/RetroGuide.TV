import Foundation

/// Measures a lineup's schedule: how long finding what's on takes (now and
/// years ahead), how well the rules hold, whether period switches line up,
/// and whether answers are the same however they're reached. For
/// development (see `RealLibraryScheduleTests`).
public enum ScheduleDiagnostics {
    public enum Tuning {
        /// Rules are measured over this stretch from now.
        public static let ruleDays = 90.0
        static let fairnessDays = 28.0
        /// Period switches checked, from a year back to about 25 years ahead.
        public static let switches = -13...325
        static let determinismSamples = 500
        static let determinismDays = 400.0
    }

    public struct Metrics: CustomStringConvertible, Sendable {
        var programs = 0
        var overLimitShare = 0.0
        var sameEpisodeShare = 0.0
        var highestSimulcast = 0
        var continuityBreaks = 0
        var gaps = 0
        var showsAiredShare = 0.0
        var airtimeSpread = 0.0

        public var description: String {
            String(
                format: "programs %d | over show limit %.3f%% | same episode at once %.3f%% (max %d channels) | continuity breaks %d | gaps %d | shows aired in 28 days %.0f%% | airtime spread (max/min share, median) %.2f",
                programs, overLimitShare * 100, sameEpisodeShare * 100, highestSimulcast, continuityBreaks, gaps, showsAiredShare * 100, airtimeSpread
            )
        }
    }

    /// The full report as text, building fresh lineups from `index` as the app does.
    public static func report(
        index: LibraryIndex,
        curated: [ChannelDefinition],
        grid: ScheduleGrid,
        customization: LineupCustomization,
        now: Date = .now
    ) -> String {
        var lines: [String] = []
        func log(_ line: String) {
            lines.append(line)
        }
        let options = LineupOptions.adapted(to: index, grid: grid)
        func build() -> [Channel] {
            LineupBuilder(curated: curated, options: options).build(index: index, customization: customization)
        }
        for years in [0.0, 5, 20] {
            let date = now.addingTimeInterval(years * 365.25 * 86_400)
            var lineup: [Channel] = []
            let building = seconds { lineup = build() }
            let warming = seconds {
                for channel in lineup where !channel.isHidden {
                    _ = channel.timeline.program(at: date)
                }
            }
            log(String(format: "+%.0f years: build lineup %.0f ms, find what's on (every visible channel) %.0f ms", years, building * 1_000, warming * 1_000))
        }
        let lineup = build()
        let visible = lineup.filter { !$0.isHidden }
        let guide = seconds {
            for channel in visible {
                _ = channel.timeline.programs(overlapping: DateInterval(start: now, duration: 3 * 3_600))
            }
        }
        let week = seconds {
            for channel in visible {
                _ = channel.timeline.programs(overlapping: DateInterval(start: now, duration: 7 * 86_400))
            }
        }
        log(String(format: "guide, every visible channel: next 3 hours %.0f ms, next 7 days %.0f ms", guide * 1_000, week * 1_000))
        log("channels \(lineup.count), visible \(visible.count), items \(index.items.count), grid \(grid), limit \(customization.simulcastLimit)")
        let window = DateInterval(start: now, duration: Tuning.ruleDays * 86_400)
        log("next \(Int(Tuning.ruleDays)) days: \(metrics(lineup, window: window, limit: customization.simulcastLimit))")

        // The shared channels as the lineup schedules them, to compare runs at each period switch.
        let shared = lineup.filter { !$0.isHidden && !($0.definition.source == .series && Channel.airsOneShow($0.items)) && !($0.definition.source == .custom && Channel.airsOneShow($0.items)) }
        let coordinator = SimulcastCoordinator(
            limit: customization.simulcastLimit.channels ?? .max,
            channels: shared.sorted { $0.id < $1.id }.map { (ScheduleContext(channelID: $0.id, items: $0.items, grid: grid), $0.definition.ordering) }
        )
        let current = SimulcastCoordinator.period(containing: ScheduleTime.milliseconds(since: now))
        var seamless = 0, total = 0, imperfect: [Int] = []
        let switching = seconds {
            for offset in Tuning.switches {
                let result = coordinator.seamlessChannels(at: current + offset)
                seamless += result.seamless
                total += result.of
                if result.seamless < result.of { imperfect.append(offset) }
            }
        }
        log(String(format: "period switches (%d, %.0f ms): %d of %d channel switches seamless%@", Tuning.switches.count, switching * 1_000, seamless, total, imperfect.isEmpty ? "" : ", imperfect at periods \(imperfect.prefix(10))"))

        // Content versions: how many times each channel's content changed.
        let versions = visible.map { channel in Set(channel.items.map { ContentVersions.effectiveTime(addedAt: $0.addedAt) }).count }.sorted()
        let dated = index.items.filter { $0.addedAt != nil }.count
        log("content versions per visible channel: median \(versions[safe: versions.count / 2] ?? 0), max \(versions.last ?? 0); items with an added date \(dated) of \(index.items.count)")
        log(stability(index: index, curated: curated, options: options, customization: customization, now: now))

        let again = build()
        var generator = SeededGenerator(seed: 42)
        var mismatches = 0
        for _ in 0..<Tuning.determinismSamples {
            let position = Int.random(in: lineup.indices, using: &generator)
            let date = now.addingTimeInterval(TimeInterval.random(in: 0..<(Tuning.determinismDays * 86_400), using: &generator))
            if lineup[position].timeline.program(at: date) != again[position].timeline.program(at: date) {
                mismatches += 1
            }
        }
        log("same answers from a fresh lineup: \(Tuning.determinismSamples - mismatches) of \(Tuning.determinismSamples)")
        log("")
        log("lineup report (fixed reference week):")
        log(LineupReport(lineup: lineup, index: index, simulcastLimit: customization.simulcastLimit).description)
        return lines.joined(separator: "\n")
    }


    /// Pretends the items added in the last week were added just now, and
    /// compares every channel with and without them: nothing before the
    /// next broadcast-day boundary should differ, and after it shows should
    /// carry on in order with the new items airing.
    private static func stability(index: LibraryIndex, curated: [ChannelDefinition], options: LineupOptions, customization: LineupCustomization, now: Date) -> String {
        let cutoff = now.addingTimeInterval(-7 * 86_400)
        var recent = index.items.filter { ($0.addedAt ?? .distantPast) > cutoff }
        if recent.isEmpty {
            recent = Array(index.items.sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }.prefix(50))
        }
        let recentIDs = Set(recent.map(\.id))
        let older = index.items.filter { !recentIDs.contains($0.id) }
        func lineup(_ items: [MediaItem]) -> [Channel] {
            LineupBuilder(curated: curated, options: options).build(index: LibraryIndex(items: items), customization: customization)
                .filter { !$0.isHidden }
        }
        let without = lineup(older)
        let with = lineup(older + recent.map { $0.withAddedAt(now) })
        let boundary = ScheduleTime.date(ContentVersions.effectiveTime(addedAt: now))
        let before = DateInterval(start: now, end: boundary)
        let byID = Dictionary(without.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var compared = 0, changedBefore = 0, breaks = 0, newAirings = 0
        var changedNames: [String] = []
        for channel in with {
            if let old = byID[channel.id] {
                compared += 1
                let a = old.timeline.programs(overlapping: before).filter { $0.start < boundary }
                let b = channel.timeline.programs(overlapping: before).filter { $0.start < boundary }
                if a.map(\.item.id) != b.map(\.item.id) || a.map(\.start) != b.map(\.start) {
                    changedBefore += 1
                    if changedNames.count < 5 { changedNames.append(channel.id) }
                }
            }
            // After the boundary: every show's next episode, in broadcast order as of each program.
            let after = channel.timeline.programs(overlapping: DateInterval(start: boundary.addingTimeInterval(-86_400), duration: 3 * 86_400))
            var episodesByShow: [String: [MediaItem]] = [:]
            for item in channel.items { episodesByShow[item.showID, default: []].append(item) }
            for key in episodesByShow.keys { episodesByShow[key]?.sort(by: broadcastOrder) }
            var expected: [String: String] = [:]
            for program in after {
                let show = program.item.showID
                let time = ScheduleTime.milliseconds(since: program.start)
                let episodes = (episodesByShow[show] ?? []).filter { ContentVersions.effectiveTime(addedAt: $0.addedAt) <= time }
                guard let index = episodes.firstIndex(where: { $0.id == program.item.id }) else { continue }
                if let next = expected[show], next != program.item.id { breaks += 1 }
                expected[show] = episodes[(index + 1) % episodes.count].id
                if recentIDs.contains(program.item.id) { newAirings += 1 }
            }
        }
        return "stability (\(recent.count) recent items re-added now, boundary in \(Int(boundary.timeIntervalSince(now) / 60)) min): "
            + "\(changedBefore) of \(compared) channels changed before the boundary\(changedNames.isEmpty ? "" : " \(changedNames)"); "
            + "after it: \(breaks) continuity breaks (the coordinator may defer a turn; nominal order has none), \(newAirings) airings of the new items in 2 days"
    }

    private static func seconds(_ work: () -> Void) -> Double {
        let start = ContinuousClock.now
        work()
        let elapsed = (ContinuousClock.now - start).components
        return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    }

    // MARK: - Metrics

    public static func metrics(_ lineup: [Channel], window: DateInterval, limit: SimulcastLimit) -> Metrics {
        var metrics = Metrics()
        let visible = lineup.filter { !$0.isHidden }
        var programs: [String: [ScheduledProgram]] = [:]
        for channel in visible {
            let airings = channel.timeline.programs(overlapping: window)
            programs[channel.id] = airings
            metrics.programs += airings.count
            for (previous, next) in zip(airings, airings.dropFirst()) where abs(next.start.timeIntervalSince(previous.slotEnd)) > 1 {
                metrics.gaps += 1
            }
            metrics.continuityBreaks += continuityBreaks(airings, items: channel.items)
        }
        let counted = visible.filter { ![.series, .custom].contains($0.definition.source) }
        let shows = overlap(counted.flatMap { programs[$0.id] ?? [] }, window: window, key: \.showID, limit: limit.channels)
        metrics.overLimitShare = shows.share
        let episodes = overlap(visible.flatMap { programs[$0.id] ?? [] }, window: window, key: \.id, limit: 1)
        metrics.sameEpisodeShare = episodes.share
        metrics.highestSimulcast = episodes.highest

        // Fairness over the first four weeks, on channels with several shows.
        let fairness = DateInterval(start: window.start, duration: Tuning.fairnessDays * 24 * 3_600)
        var aired: [Double] = []
        var spreads: [Double] = []
        for channel in visible {
            let shows = Set(channel.items.map(\.showID))
            guard shows.count >= 3 else { continue }
            var airtime: [String: TimeInterval] = [:]
            for program in programs[channel.id] ?? [] where fairness.contains(program.start) {
                airtime[program.item.showID, default: 0] += program.slotEnd.timeIntervalSince(program.start)
            }
            aired.append(Double(airtime.count) / Double(shows.count))
            if let high = airtime.values.max(), let low = airtime.values.min(), low > 0 {
                spreads.append(high / low)
            }
        }
        metrics.showsAiredShare = aired.isEmpty ? 0 : aired.reduce(0, +) / Double(aired.count)
        metrics.airtimeSpread = spreads.sorted()[safe: spreads.count / 2] ?? 0
        return metrics
    }

    /// Times a show's next airing on a channel isn't its next episode (wrapping after the last).
    private static func continuityBreaks(_ programs: [ScheduledProgram], items: [MediaItem]) -> Int {
        var grouped: [String: [MediaItem]] = [:]
        for item in items {
            grouped[item.showID, default: []].append(item)
        }
        var position: [String: [String: Int]] = [:]
        var counts: [String: Int] = [:]
        for (show, episodes) in grouped {
            let sorted = episodes.sorted(by: broadcastOrder)
            counts[show] = sorted.count
            var indices: [String: Int] = [:]
            for (index, item) in sorted.enumerated() {
                indices[item.id] = index
            }
            position[show] = indices
        }
        var expected: [String: Int] = [:]
        var breaks = 0
        for program in programs {
            let show = program.item.showID
            guard let index = position[show]?[program.item.id], let count = counts[show] else { continue }
            if let next = expected[show], next != index {
                breaks += 1
            }
            expected[show] = (index + 1) % count
        }
        return breaks
    }

    private static func broadcastOrder(_ lhs: MediaItem, _ rhs: MediaItem) -> Bool {
        let left = lhs.series?.broadcastOrder ?? (0, 0)
        let right = rhs.series?.broadcastOrder ?? (0, 0)
        return left != right ? left < right : lhs.id < rhs.id
    }

    /// Share of the window in which some key airs on more than `limit` channels, and the most at once.
    private static func overlap(_ programs: [ScheduledProgram], window: DateInterval, key: (MediaItem) -> String, limit: Int?) -> (share: Double, highest: Int) {
        var events: [(time: Date, change: Int, key: String)] = []
        for program in programs {
            let start = max(program.start, window.start), end = min(program.slotEnd, window.end)
            guard start < end else { continue }
            let value = key(program.item)
            events.append((start, 1, value))
            events.append((end, -1, value))
        }
        events.sort { ($0.time, $0.change) < ($1.time, $1.change) }
        var airing: [String: Int] = [:]
        var over = 0
        var since: Date?
        var total: TimeInterval = 0
        var highest = 0
        for event in events {
            let before = airing[event.key, default: 0]
            let after = before + event.change
            airing[event.key] = after
            highest = max(highest, after)
            guard let limit else { continue }
            if before <= limit, after > limit {
                if over == 0 { since = event.time }
                over += 1
            } else if before > limit, after <= limit {
                over -= 1
                if over == 0, let since { total += event.time.timeIntervalSince(since) }
            }
        }
        return (total / window.duration, highest)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
