import Foundation

/// Schedules a group of channels together so that no show is on more than
/// `limit` of them at the same moment, and no episode or movie is on two
/// channels at once (including the fixed 24/7 channels around them).
///
/// Every channel follows its ``NominalOrder``, simulated side by side with
/// the others, always advancing the channel whose next program starts first.
/// A channel about to air a show that's already on `limit` others, or an
/// episode that's already on, airs a later program early and comes back to
/// the one it passed over (``TrackingPicker``). Channels that don't count
/// toward the limit (custom channels) still avoid airing the same episode.
///
/// Nothing is replayed from the epoch. Time is cut into periods, and each
/// period is simulated on its own, starting a warm-up before it with every
/// channel exactly on its order (arithmetic, the same cost in any year).
/// Channels always return to their order after stepping around a clash, so
/// runs started at different times end up in exactly the same state: by the
/// time a period begins, its run and the previous period's agree, and the
/// handover can't be seen. The result depends only on the lineup, so every
/// device shows the same guide, and finding what's on costs the same today
/// as in twenty years.
final class SimulcastCoordinator: @unchecked Sendable {
    enum Tuning {
        static let period = 28 * ScheduleTime.perDay
        /// How long before its period a run starts. Runs agree after about
        /// four days on a large library; twice that and more for margin.
        static let warmUp = 14 * ScheduleTime.perDay
        /// Periods start at 09:00 UTC (about 4–5 am in the US).
        static let periodStart = 9 * 60 * 60 * ScheduleTime.perSecond
        /// Programs kept from before a period starts, to compare runs (``seamlessChannels(at:)``).
        static let overlap = ScheduleTime.perDay
        static let cachedPeriods = 3
    }

    private let limit: Int
    private let contexts: [ScheduleContext]
    private let orders: [(any NominalOrder)?]
    /// Show and item of every channel's items, as indices shared by all channels.
    private let globalShow: [[Int]]
    private let globalItem: [[Int]]
    private let showCount: Int
    private let itemCount: Int
    /// Whether each channel's airings count toward `limit`.
    private let countsTowardLimit: [Bool]
    /// When fixed channels air each item (by shared item index), if ever.
    private let fixedSlots: [[RepeatingSlot]]
    /// Channels with anything to air.
    private let activeChannels: [Int]

    private let lock = NSLock()
    private var runs: [Int: Run] = [:]
    private var runRecency: [Int] = []

    /// One period's simulation: every channel's programs, from `overlap`
    /// before the period until the next period's run takes over.
    private struct Run {
        var items: [[Int]]
        var starts: [[Int]]
    }

    /// - Parameters:
    ///   - uncounted: positions of channels that don't count toward `limit`.
    ///   - fixed: items' slots on channels outside the group (24/7 channels),
    ///     which the group works around.
    init(
        limit: Int,
        channels: [(context: ScheduleContext, ordering: ScheduleOrdering)],
        uncounted: Set<Int> = [],
        fixed: [(item: MediaItem, slot: RepeatingSlot)] = []
    ) {
        self.limit = limit
        contexts = channels.map(\.context)
        countsTowardLimit = channels.indices.map { !uncounted.contains($0) }
        let keeps = ShowBudget.keeps(channels.indices.map { ShowBudget.Channel(context: channels[$0].context, ordering: channels[$0].ordering, counts: !uncounted.contains($0)) }, limit: limit)
        orders = channels.indices.map { channel in
            channels[channel].context.isEmpty ? nil : NominalOrders.make(ordering: channels[channel].ordering, context: channels[channel].context, keep: keeps[channel])
        }
        var itemIDs: [String: Int] = [:]
        globalItem = channels.map { channel in
            channel.context.items.map { item in
                if let known = itemIDs[item.id] { return known }
                itemIDs[item.id] = itemIDs.count
                return itemIDs.count - 1
            }
        }
        itemCount = itemIDs.count
        var fixedSlots = Array(repeating: [RepeatingSlot](), count: itemIDs.count)
        for (item, slot) in fixed {
            if let index = itemIDs[item.id] { fixedSlots[index].append(slot) }
        }
        self.fixedSlots = fixedSlots
        var showIDs: [String: Int] = [:]
        for id in Set(channels.flatMap(\.context.showIDs)).sorted() {
            showIDs[id] = showIDs.count
        }
        showCount = showIDs.count
        globalShow = channels.map { channel in
            channel.context.showOfItem.map { channel.context.showIDs.isEmpty ? 0 : showIDs[channel.context.showIDs[$0]] ?? 0 }
        }
        activeChannels = channels.indices.filter { !channels[$0].context.isEmpty }
    }

    /// The schedule of the channel at `position` (in the order given to `init`).
    func timeline(for position: Int) -> ChannelSchedule {
        CoordinatedTimeline(coordinator: self, position: position)
    }

    static func periodStart(_ period: Int) -> Int {
        Tuning.periodStart + period * Tuning.period
    }

    static func period(containing offset: Int) -> Int {
        Int((Double(offset - Tuning.periodStart) / Double(Tuning.period)).rounded(.down))
    }

    // MARK: - Queries

    fileprivate func isEmpty(_ channel: Int) -> Bool {
        contexts[channel].isEmpty
    }

    fileprivate func channelID(_ channel: Int) -> String {
        contexts[channel].channelID
    }

    /// The program airing at `date`: each period shows its own run's
    /// programs that start within it, after the last one from before.
    fileprivate func program(at date: Date, channel: Int) -> ScheduledProgram? {
        let offset = ScheduleTime.milliseconds(since: date)
        guard !contexts[channel].isEmpty, offset >= .zero else { return nil }
        lock.lock()
        defer { lock.unlock() }
        let period = Self.period(containing: offset)
        let starts = run(period).starts[channel]
        if let slot = Self.lastIndex(in: starts, notAfter: offset), starts[slot] >= Self.periodStart(period) {
            return makeProgram(channel: channel, period: period, slot: slot)
        }
        guard let slot = Self.lastIndex(in: run(period - 1).starts[channel], notAfter: offset) else { return nil }
        return makeProgram(channel: channel, period: period - 1, slot: slot)
    }

    fileprivate func program(after program: ScheduledProgram, channel: Int) -> ScheduledProgram? {
        guard !contexts[channel].isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        let period = program.cycle
        let starts = run(period).starts[channel]
        let end = Self.periodStart(period + 1)
        if program.slot + 1 < starts.count, starts[program.slot + 1] < end {
            return makeProgram(channel: channel, period: period, slot: program.slot + 1)
        }
        // The next run takes over with its first program starting in its period.
        let next = run(period + 1).starts[channel]
        let slot = Self.lastIndex(in: next, notAfter: end - 1).map { $0 + 1 } ?? 0
        guard slot < next.count else { return nil }
        return makeProgram(channel: channel, period: period + 1, slot: slot)
    }

    private func makeProgram(channel: Int, period: Int, slot: Int) -> ScheduledProgram {
        let run = run(period)
        return contexts[channel].program(item: run.items[channel][slot], start: run.starts[channel][slot], cycle: period, slot: slot)
    }

    /// Index of the last of the ascending `starts` at or before `offset`.
    private static func lastIndex(in starts: [Int], notAfter offset: Int) -> Int? {
        var low = 0
        var high = starts.count
        while low < high {
            let middle = (low + high) / 2
            if starts[middle] <= offset {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low > 0 ? low - 1 : nil
    }

    // MARK: - Handover

    /// How many channels' runs agree around the start of `period`: the
    /// previous period's run and this one air the same programs at the same
    /// times from a day before to a day after.
    func seamlessChannels(at period: Int) -> (seamless: Int, of: Int) {
        lock.lock()
        defer { lock.unlock() }
        let start = Self.periodStart(period)
        let before = run(period - 1)
        let after = run(period)
        func around(_ run: Run, _ channel: Int) -> [Int] {
            zip(run.starts[channel], run.items[channel])
                .filter { abs($0.0 - start) < Tuning.overlap }
                .flatMap { [$0.0, $0.1] }
        }
        let seamless = activeChannels.filter { around(before, $0) == around(after, $0) }.count
        return (seamless, activeChannels.count)
    }

    // MARK: - Simulation

    private func run(_ period: Int) -> Run {
        if let cached = runs[period] {
            runRecency.removeAll { $0 == period }
            runRecency.append(period)
            return cached
        }
        let built = simulate(period)
        runs[period] = built
        runRecency.append(period)
        while runRecency.count > Tuning.cachedPeriods {
            runs[runRecency.removeFirst()] = nil
        }
        return built
    }

    /// Everything needed to continue all channels from one moment.
    private struct State {
        var pickers: [TrackingPicker?]
        /// Show each channel is airing (-1: none, or it doesn't count toward
        /// the limit), and how many channels air each show.
        var airing: [Int]
        var airingCount: [Int]
        /// Item each channel is airing (-1: none yet), and how many channels air each item.
        var airingItem: [Int]
        var itemAiringCount: [Int]
    }

    private func simulate(_ period: Int) -> Run {
        let start = Self.periodStart(period)
        let begin = max(start - Tuning.warmUp, .zero)
        let end = Self.periodStart(period + 1) + Tuning.overlap
        let keepFrom = start - Tuning.overlap
        var state = State(
            pickers: Array(repeating: nil, count: contexts.count),
            airing: Array(repeating: -1, count: contexts.count),
            airingCount: Array(repeating: 0, count: showCount),
            airingItem: Array(repeating: -1, count: contexts.count),
            itemAiringCount: Array(repeating: 0, count: itemCount)
        )
        var firstStarts: [(Int, Int)] = []
        for channel in activeChannels {
            guard let order = orders[channel] else { continue }
            let position = order.position(at: begin)
            state.pickers[channel] = TrackingPicker(order: order, at: position)
            firstStarts.append((order.start(of: position), channel))
        }
        var run = Run(items: Array(repeating: [], count: contexts.count), starts: Array(repeating: [], count: contexts.count))
        var upcoming = StartQueue(firstStarts)
        var due: [Int] = []
        func pick(_ channel: Int, at start: Int) -> Int {
            let (item, next) = self.pick(on: channel, at: start, state: &state)
            if start >= keepFrom {
                run.items[channel].append(item)
                run.starts[channel].append(start)
            }
            return next
        }
        while let earliest = upcoming.peek, earliest < end {
            // Usually one channel starts at a time: pick and move it down the
            // queue in one step.
            if upcoming.isTopUnique, let channel = upcoming.topChannel {
                endProgram(on: channel, state: &state)
                upcoming.replaceTop(pick(channel, at: earliest))
                continue
            }
            // Every channel starting now; their previous programs end, so they
            // stop counting before anyone picks.
            due.removeAll(keepingCapacity: true)
            while upcoming.peek == earliest, let channel = upcoming.pop() {
                due.append(channel)
                endProgram(on: channel, state: &state)
            }
            // Of channels starting together, those with the fewest shows to
            // choose from pick first (a channel carrying A and B can step
            // aside for one carrying only A); equals take turns going first,
            // by the time rather than by how long the run has gone, so runs
            // started at different times agree.
            let rotation = earliest / (60 * ScheduleTime.perSecond)
            due.sort { lhs, rhs in
                let left = contexts[lhs].shows.count, right = contexts[rhs].shows.count
                return left != right ? left < right : (lhs + rotation) % contexts.count < (rhs + rotation) % contexts.count
            }
            for channel in due {
                upcoming.push(pick(channel, at: earliest), channel)
            }
        }
        return run
    }

    private func endProgram(on channel: Int, state: inout State) {
        if state.airing[channel] >= 0 {
            state.airingCount[state.airing[channel]] -= 1
            state.airing[channel] = -1
        }
        if state.airingItem[channel] >= 0 {
            state.itemAiringCount[state.airingItem[channel]] -= 1
            state.airingItem[channel] = -1
        }
    }

    /// Airs the channel's next program at `start`; returns it and when it ends.
    private func pick(on channel: Int, at start: Int, state: inout State) -> (item: Int, end: Int) {
        let context = contexts[channel]
        let shows = globalShow[channel]
        let items = globalItem[channel]
        let counts = countsTowardLimit[channel]
        // Moved out while it runs, so its arrays aren't copied.
        guard var picker = state.pickers[channel] else { preconditionFailure("no picker for an active channel") }
        state.pickers[channel] = nil
        // The same episode on two channels never bends; the show limit may,
        // when nothing else could air.
        func isFree(_ candidate: Int) -> Bool {
            state.itemAiringCount[items[candidate]] == 0
                && !isOnFixedChannel(items[candidate], from: start, to: start + context.slotLengths[candidate])
        }
        let item = picker.next(
            isAllowed: { (!counts || state.airingCount[shows[$0]] < limit) && isFree($0) },
            isAcceptable: isFree
        )
        state.pickers[channel] = picker
        if counts {
            state.airing[channel] = shows[item]
            state.airingCount[shows[item]] += 1
        }
        state.airingItem[channel] = items[item]
        state.itemAiringCount[items[item]] += 1
        return (item, start + context.slotLengths[item])
    }

    /// Whether a 24/7 channel airs the item at any point in `start..<end` (milliseconds).
    private func isOnFixedChannel(_ item: Int, from start: Int, to end: Int) -> Bool {
        fixedSlots[item].contains { $0.overlaps(from: ScheduleTime.seconds(start), to: ScheduleTime.seconds(end)) }
    }
}

/// One channel's view of a ``SimulcastCoordinator``.
private final class CoordinatedTimeline: ChannelSchedule {
    let coordinator: SimulcastCoordinator
    let position: Int

    init(coordinator: SimulcastCoordinator, position: Int) {
        self.coordinator = coordinator
        self.position = position
    }

    var channelID: String {
        coordinator.channelID(position)
    }

    var isEmpty: Bool {
        coordinator.isEmpty(position)
    }

    func program(at date: Date) -> ScheduledProgram? {
        coordinator.program(at: date, channel: position)
    }

    func program(after program: ScheduledProgram) -> ScheduledProgram? {
        coordinator.program(after: program, channel: position)
    }
}
