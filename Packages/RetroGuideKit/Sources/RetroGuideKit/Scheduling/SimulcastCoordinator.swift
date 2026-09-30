import Foundation

/// Schedules a group of channels together so that no show is on more than
/// `limit` of them at the same moment, and no episode or movie is on two
/// channels at once (including the fixed 24/7 channels around them).
///
/// All channels are simulated side by side from ``ScheduleConstants/epoch``,
/// always advancing the channel whose next program starts first. A channel
/// about to air a show that's already on `limit` others, or an episode that's
/// already on, passes that turn and airs something else, and the show
/// continues where it left off later. Only real clashes are avoided, so
/// channels keep their full variety. Channels that don't count toward the
/// limit (custom channels) still avoid airing the same episode. The result
/// depends only on the lineup, so every device shows the same guide.
///
/// Simulated days are cached, with the state needed to continue from them.
final class SimulcastCoordinator: @unchecked Sendable {
    enum Tuning {
        /// Programs are simulated and cached one day at a time.
        static let chunkLength: TimeInterval = 24 * ScheduleConstants.secondsPerHour
        static let cachedChunks = 8
        /// Continuation points kept (besides the epoch), and how far apart.
        static let cachedCheckpoints = 6
        static let checkpointSpacing = 7
    }

    private let limit: Int
    private let contexts: [ScheduleContext]
    /// Show and item of every channel's items, as indices shared by all channels.
    private let globalShow: [[Int]]
    private let globalItem: [[Int]]
    private let showCount: Int
    /// Whether each channel's airings count toward `limit`.
    private let countsTowardLimit: [Bool]
    /// When fixed channels air each item (by shared item index), if ever.
    private let fixedSlots: [[RepeatingSlot]]
    /// Channels with anything to air.
    private let activeChannels: [Int]
    private let initial: State

    private let lock = NSLock()
    private var chunks: [Int: Chunk] = [:]
    private var chunkRecency: [Int] = []
    private var checkpoints: [Int: State] = [:]

    /// Everything needed to continue all channels from one moment.
    private struct State {
        var pickers: [ChannelPicker]
        /// When each channel's next program starts.
        var nextStart: [TimeInterval]
        /// Show each channel is airing (-1: none, or it doesn't count toward
        /// the limit), and how many channels air each show.
        var airing: [Int]
        var airingCount: [Int]
        /// Item each channel is airing (-1: none yet), and how many channels air each item.
        var airingItem: [Int]
        var itemAiringCount: [Int]
        /// Advances with every group of channels starting together, to rotate
        /// which of equally constrained channels picks first.
        var startGroups = 0
    }

    /// Programs starting within one chunk, per channel.
    private struct Chunk {
        var items: [[Int]]
        var starts: [[TimeInterval]]
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
        self.contexts = channels.map(\.context)
        self.countsTowardLimit = channels.indices.map { !uncounted.contains($0) }
        var itemIDs: [String: Int] = [:]
        self.globalItem = channels.map { channel in
            channel.context.items.map { item in
                if let known = itemIDs[item.id] { return known }
                itemIDs[item.id] = itemIDs.count
                return itemIDs.count - 1
            }
        }
        var fixedSlots = Array(repeating: [RepeatingSlot](), count: itemIDs.count)
        for (item, slot) in fixed {
            if let index = itemIDs[item.id] { fixedSlots[index].append(slot) }
        }
        self.fixedSlots = fixedSlots
        var ids: [String: Int] = [:]
        for id in Set(channels.flatMap(\.context.showIDs)).sorted() {
            ids[id] = ids.count
        }
        self.showCount = ids.count
        self.activeChannels = channels.indices.filter { !channels[$0].context.isEmpty }
        self.globalShow = channels.map { channel in
            channel.context.showOfItem.map { ids[channel.context.showIDs.isEmpty ? "" : channel.context.showIDs[$0]] ?? 0 }
        }
        self.initial = State(
            pickers: channels.map { ChannelPicker(ordering: $0.ordering, context: $0.context) },
            nextStart: Array(repeating: .zero, count: channels.count),
            airing: Array(repeating: -1, count: channels.count),
            airingCount: Array(repeating: 0, count: ids.count),
            airingItem: Array(repeating: -1, count: channels.count),
            itemAiringCount: Array(repeating: 0, count: itemIDs.count)
        )
    }

    /// The schedule of the channel at `position` (in the order given to `init`).
    func timeline(for position: Int) -> ChannelSchedule {
        CoordinatedTimeline(coordinator: self, position: position)
    }

    // MARK: - Queries

    fileprivate func isEmpty(_ channel: Int) -> Bool {
        contexts[channel].isEmpty
    }

    fileprivate func program(at date: Date, channel: Int) -> ScheduledProgram? {
        guard !contexts[channel].isEmpty else { return nil }
        let offset = date.timeIntervalSince(ScheduleConstants.epoch)
        guard offset >= .zero else { return nil }
        lock.lock()
        defer { lock.unlock() }
        // The program airing is the last one starting at or before `offset`,
        // in this chunk or (for a program running past midnight) an earlier one.
        var number = Int(offset / Tuning.chunkLength)
        while number >= 0 {
            let starts = chunk(number).starts[channel]
            if let slot = starts.lastIndex(where: { $0 <= offset }) {
                return makeProgram(channel: channel, chunk: number, slot: slot)
            }
            number -= 1
        }
        return nil
    }

    fileprivate func program(after program: ScheduledProgram, channel: Int) -> ScheduledProgram? {
        guard !contexts[channel].isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if program.slot + 1 < chunk(program.cycle).items[channel].count {
            return makeProgram(channel: channel, chunk: program.cycle, slot: program.slot + 1)
        }
        var number = program.cycle + 1
        while chunk(number).items[channel].isEmpty {
            number += 1
        }
        return makeProgram(channel: channel, chunk: number, slot: .zero)
    }

    private func makeProgram(channel: Int, chunk number: Int, slot: Int) -> ScheduledProgram {
        let context = contexts[channel]
        let chunk = chunk(number)
        let index = chunk.items[channel][slot]
        let item = context.items[index]
        let start = ScheduleConstants.epoch.addingTimeInterval(chunk.starts[channel][slot])
        return ScheduledProgram(
            channelID: context.channelID,
            item: item,
            start: start,
            contentEnd: start.addingTimeInterval(item.duration),
            slotEnd: start.addingTimeInterval(context.slotLengths[index]),
            cycle: number,
            slot: slot
        )
    }

    // MARK: - Simulation

    private func chunk(_ number: Int) -> Chunk {
        if let cached = chunks[number] {
            touch(number)
            return cached
        }
        let from = checkpoints.keys.filter { $0 <= number }.max()
        var state = from.flatMap { checkpoints[$0] } ?? initial
        var current = from ?? 0
        var built = Chunk(items: [], starts: [])
        while current <= number {
            if current % Tuning.checkpointSpacing == 0, checkpoints[current] == nil {
                checkpoints[current] = state
                trimCheckpoints(keeping: number)
            }
            let chunk = simulate(chunk: current, state: &state)
            if current >= number - 1 {
                store(chunk, as: current)
            }
            built = chunk
            current += 1
        }
        return built
    }

    private func simulate(chunk number: Int, state: inout State) -> Chunk {
        let end = Double(number + 1) * Tuning.chunkLength
        var chunk = Chunk(items: Array(repeating: [], count: contexts.count), starts: Array(repeating: [], count: contexts.count))
        var upcoming = StartQueue(activeChannels.map { (state.nextStart[$0], $0) })
        var due: [Int] = []
        while let earliest = upcoming.peek, earliest < end {
            // Usually one channel starts at a time: pick and move it down the
            // queue in one step.
            if upcoming.isTopUnique, let channel = upcoming.topChannel {
                endProgram(on: channel, state: &state)
                upcoming.replaceTop(pick(on: channel, at: earliest, state: &state, chunk: &chunk))
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
            // aside for one carrying only A); equals take turns going first.
            state.startGroups += 1
            let rotation = state.startGroups
            due.sort { lhs, rhs in
                let left = contexts[lhs].shows.count, right = contexts[rhs].shows.count
                return left != right ? left < right : (lhs + rotation) % contexts.count < (rhs + rotation) % contexts.count
            }
            for channel in due {
                upcoming.push(pick(on: channel, at: earliest, state: &state, chunk: &chunk), channel)
            }
        }
        return chunk
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

    /// Airs the channel's next program at `start`; returns when it ends.
    private func pick(on channel: Int, at start: TimeInterval, state: inout State, chunk: inout Chunk) -> TimeInterval {
        let context = contexts[channel]
        let shows = globalShow[channel]
        let items = globalItem[channel]
        let counts = countsTowardLimit[channel]
        // Moved out while it runs, so its arrays aren't copied.
        var picker = ChannelPicker.moving
        swap(&picker, &state.pickers[channel])
        // The same episode on two channels never bends; the show limit may,
        // when nothing else could air.
        func isFree(_ candidate: Int) -> Bool {
            state.itemAiringCount[items[candidate]] == 0
                && !isOnFixedChannel(items[candidate], from: start, to: start + context.slotLengths[candidate])
        }
        let item = picker.next(
            at: start,
            in: context,
            isAllowed: { (!counts || state.airingCount[shows[$0]] < limit) && isFree($0) },
            isAcceptable: isFree
        )
        swap(&picker, &state.pickers[channel])
        if counts {
            state.airing[channel] = shows[item]
            state.airingCount[shows[item]] += 1
        }
        state.airingItem[channel] = items[item]
        state.itemAiringCount[items[item]] += 1
        let next = start + context.slotLengths[item]
        state.nextStart[channel] = next
        chunk.items[channel].append(item)
        chunk.starts[channel].append(start)
        return next
    }

    /// Whether a 24/7 channel airs the item at any point in `start..<end`.
    private func isOnFixedChannel(_ item: Int, from start: TimeInterval, to end: TimeInterval) -> Bool {
        fixedSlots[item].contains { $0.overlaps(from: start, to: end) }
    }

    private func store(_ chunk: Chunk, as number: Int) {
        chunks[number] = chunk
        touch(number)
        while chunkRecency.count > Tuning.cachedChunks {
            chunks[chunkRecency.removeFirst()] = nil
        }
    }

    private func touch(_ number: Int) {
        chunkRecency.removeAll { $0 == number }
        chunkRecency.append(number)
    }

    private func trimCheckpoints(keeping number: Int) {
        guard checkpoints.count > Tuning.cachedCheckpoints else { return }
        let keep = Set(checkpoints.keys.sorted { abs($0 - number) < abs($1 - number) }.prefix(Tuning.cachedCheckpoints))
        checkpoints = checkpoints.filter { keep.contains($0.key) }
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

extension SimulcastCoordinator {
    fileprivate func channelID(_ channel: Int) -> String {
        contexts[channel].channelID
    }
}

/// Channels ordered by when their next program starts (then by position, so
/// the order is deterministic): a binary min-heap.
private struct StartQueue {
    private typealias Entry = (start: TimeInterval, channel: Int)

    private var heap: [Entry] = []

    init(_ entries: [(TimeInterval, Int)]) {
        heap.reserveCapacity(entries.count)
        for (start, channel) in entries {
            push(start, channel)
        }
    }

    var peek: TimeInterval? {
        heap.first?.start
    }

    var topChannel: Int? {
        heap.first?.channel
    }

    /// Whether no other channel starts at the same time as the first.
    var isTopUnique: Bool {
        guard let top = heap.first?.start else { return false }
        return (heap.count <= 1 || heap[1].start != top) && (heap.count <= 2 || heap[2].start != top)
    }

    mutating func push(_ start: TimeInterval, _ channel: Int) {
        heap.append((start, channel))
        siftUp(from: heap.count - 1)
    }

    mutating func pop() -> Int? {
        guard let top = heap.first else { return nil }
        let last = heap.removeLast()
        if !heap.isEmpty {
            heap[0] = last
            siftDown(from: 0)
        }
        return top.channel
    }

    /// Gives the first channel a new start time and restores the order.
    mutating func replaceTop(_ start: TimeInterval) {
        guard !heap.isEmpty else { return }
        heap[0].start = start
        siftDown(from: 0)
    }

    // Both sifts move entries into a hole instead of swapping, in one pass
    // over the buffer: this runs once per program on every channel.

    private mutating func siftUp(from index: Int) {
        heap.withUnsafeMutableBufferPointer { buffer in
            let moving = buffer[index]
            var hole = index
            while hole > 0 {
                let parent = (hole - 1) / 2
                guard Self.precedes(moving, buffer[parent]) else { break }
                buffer[hole] = buffer[parent]
                hole = parent
            }
            buffer[hole] = moving
        }
    }

    private mutating func siftDown(from index: Int) {
        heap.withUnsafeMutableBufferPointer { buffer in
            let count = buffer.count
            let moving = buffer[index]
            var hole = index
            while true {
                var child = 2 * hole + 1
                guard child < count else { break }
                if child + 1 < count, Self.precedes(buffer[child + 1], buffer[child]) {
                    child += 1
                }
                guard Self.precedes(buffer[child], moving) else { break }
                buffer[hole] = buffer[child]
                hole = child
            }
            buffer[hole] = moving
        }
    }

    private static func precedes(_ lhs: Entry, _ rhs: Entry) -> Bool {
        lhs.start != rhs.start ? lhs.start < rhs.start : lhs.channel < rhs.channel
    }
}
