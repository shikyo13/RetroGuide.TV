import Foundation

/// Schedules a group of channels together so that no show is on more than
/// `limit` of them at the same moment.
///
/// All channels are simulated side by side from ``ScheduleConstants/epoch``,
/// always advancing the channel whose next program starts first. A channel
/// about to air a show that's already on `limit` others passes that turn and
/// airs something else, and the show continues where it left off later. Only
/// real clashes are avoided, so channels keep their full variety. The result
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
    /// Show of every channel's items, as an index shared by all channels.
    private let globalShow: [[Int]]
    private let showCount: Int
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
        /// Show each channel is airing (-1: none yet), and how many channels air each show.
        var airing: [Int]
        var airingCount: [Int]
    }

    /// Programs starting within one chunk, per channel.
    private struct Chunk {
        var items: [[Int]]
        var starts: [[TimeInterval]]
    }

    init(limit: Int, channels: [(context: ScheduleContext, ordering: ScheduleOrdering)]) {
        self.limit = limit
        self.contexts = channels.map(\.context)
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
            airingCount: Array(repeating: 0, count: ids.count)
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
            // Every channel starting now; their previous programs end, so they
            // stop counting before anyone picks.
            due.removeAll(keepingCapacity: true)
            while upcoming.peek == earliest, let channel = upcoming.pop() {
                due.append(channel)
                if state.airing[channel] >= 0 {
                    state.airingCount[state.airing[channel]] -= 1
                    state.airing[channel] = -1
                }
            }
            // Channels starting together take turns choosing first, so none
            // always gets first pick of a popular show.
            let first = Int((earliest / ScheduleConstants.secondsPerMinute).rounded(.down)) % due.count
            for turn in due.indices {
                let channel = due[(first + turn) % due.count]
                let context = contexts[channel]
                let shows = globalShow[channel]
                // Moved out while it runs, so its arrays aren't copied.
                var picker = ChannelPicker.moving
                swap(&picker, &state.pickers[channel])
                let item = picker.next(at: earliest, in: context) { state.airingCount[shows[$0]] < limit }
                swap(&picker, &state.pickers[channel])
                let show = shows[item]
                state.airing[channel] = show
                state.airingCount[show] += 1
                let next = earliest + context.slotLengths[item]
                state.nextStart[channel] = next
                upcoming.push(next, channel)
                chunk.items[channel].append(item)
                chunk.starts[channel].append(earliest)
            }
        }
        return chunk
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
    private var heap: [(start: TimeInterval, channel: Int)] = []

    init(_ entries: [(TimeInterval, Int)]) {
        heap.reserveCapacity(entries.count)
        for (start, channel) in entries {
            push(start, channel)
        }
    }

    var peek: TimeInterval? {
        heap.first?.start
    }

    mutating func push(_ start: TimeInterval, _ channel: Int) {
        heap.append((start, channel))
        var child = heap.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard precedes(heap[child], heap[parent]) else { break }
            heap.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> Int? {
        guard let top = heap.first else { return nil }
        let last = heap.removeLast()
        guard !heap.isEmpty else { return top.channel }
        heap[0] = last
        var parent = 0
        while true {
            let left = 2 * parent + 1
            let right = left + 1
            var smallest = parent
            if left < heap.count, precedes(heap[left], heap[smallest]) { smallest = left }
            if right < heap.count, precedes(heap[right], heap[smallest]) { smallest = right }
            guard smallest != parent else { break }
            heap.swapAt(parent, smallest)
            parent = smallest
        }
        return top.channel
    }

    private func precedes(_ lhs: (start: TimeInterval, channel: Int), _ rhs: (start: TimeInterval, channel: Int)) -> Bool {
        lhs.start != rhs.start ? lhs.start < rhs.start : lhs.channel < rhs.channel
    }
}
