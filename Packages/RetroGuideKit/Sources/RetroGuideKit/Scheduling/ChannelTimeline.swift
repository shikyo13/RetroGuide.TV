import Foundation

/// An endless, deterministic broadcast schedule for one channel.
///
/// Time since ``ScheduleConstants/epoch`` is split into back-to-back *cycles*.
/// Each cycle airs every item on the channel exactly once, in an order derived
/// from a seed of the channel id and the cycle number. Finding the program at
/// any instant is O(log n) after the cycle's layout is built, and nothing has
/// to be stored or regenerated as time passes.
public final class ChannelTimeline: @unchecked Sendable {
    public let channelID: String
    private let items: [MediaItem]
    private let slotLengths: [TimeInterval]
    private let ordering: ScheduleOrdering
    private let grid: ScheduleGrid
    private let cycleLength: TimeInterval
    private let baseSeed: UInt64

    private let lock = NSLock()
    private var layoutCache: [Int: CycleLayout] = [:]
    private var layoutRecency: [Int] = []

    init(channelID: String, items: [MediaItem], ordering: ScheduleOrdering, grid: ScheduleGrid) {
        self.channelID = channelID
        self.items = items
        self.ordering = ordering
        self.grid = grid
        self.slotLengths = items.map { grid.slotLength(for: $0.duration) }
        self.cycleLength = slotLengths.reduce(.zero, +)
        self.baseSeed = StableHash.fnv1a(channelID)
    }

    public var isEmpty: Bool {
        cycleLength <= .zero
    }

    /// The program airing at `date`.
    public func program(at date: Date) -> ScheduledProgram? {
        guard !isEmpty else { return nil }
        let elapsed = date.timeIntervalSince(ScheduleConstants.epoch)
        let cycle = Int((elapsed / cycleLength).rounded(.down))
        let offset = elapsed - Double(cycle) * cycleLength
        let layout = layout(forCycle: cycle)
        return makeProgram(cycle: cycle, slot: layout.slot(containing: offset), layout: layout)
    }

    /// The program that follows `program` on this channel.
    public func program(after program: ScheduledProgram) -> ScheduledProgram? {
        guard !isEmpty else { return nil }
        let layout = layout(forCycle: program.cycle)
        if program.slot + 1 < layout.order.count {
            return makeProgram(cycle: program.cycle, slot: program.slot + 1, layout: layout)
        }
        let nextCycle = program.cycle + 1
        return makeProgram(cycle: nextCycle, slot: .zero, layout: self.layout(forCycle: nextCycle))
    }

    /// Every program overlapping `interval`, in airing order.
    public func programs(overlapping interval: DateInterval) -> [ScheduledProgram] {
        guard var current = program(at: interval.start) else { return [] }
        var result = [current]
        while current.slotEnd < interval.end, let next = program(after: current) {
            result.append(next)
            current = next
        }
        return result
    }

    // MARK: - Layout

    private func makeProgram(cycle: Int, slot: Int, layout: CycleLayout) -> ScheduledProgram {
        let itemIndex = layout.order[slot]
        let cycleStart = ScheduleConstants.epoch.addingTimeInterval(Double(cycle) * cycleLength)
        let start = cycleStart.addingTimeInterval(layout.startOffsets[slot])
        let item = items[itemIndex]
        return ScheduledProgram(
            channelID: channelID,
            item: item,
            start: start,
            contentEnd: start.addingTimeInterval(item.duration),
            slotEnd: start.addingTimeInterval(slotLengths[itemIndex]),
            cycle: cycle,
            slot: slot
        )
    }

    private func layout(forCycle cycle: Int) -> CycleLayout {
        lock.lock()
        defer { lock.unlock() }
        if let cached = layoutCache[cycle] {
            touch(cycle)
            return cached
        }
        var generator = SeededGenerator(seed: baseSeed ^ StableHash.fnv1a(String(cycle)))
        let order = PlaylistArranger.arrange(items, ordering: ordering, using: &generator)
        let layout = CycleLayout(order: order, slotLengths: slotLengths)
        layoutCache[cycle] = layout
        touch(cycle)
        evictIfNeeded()
        return layout
    }

    private func touch(_ cycle: Int) {
        layoutRecency.removeAll { $0 == cycle }
        layoutRecency.append(cycle)
    }

    private func evictIfNeeded() {
        while layoutRecency.count > ScheduleConstants.cachedCyclesPerChannel {
            layoutCache[layoutRecency.removeFirst()] = nil
        }
    }
}

/// The order and start offsets of every slot in one cycle.
private struct CycleLayout {
    let order: [Int]
    let startOffsets: [TimeInterval]

    init(order: [Int], slotLengths: [TimeInterval]) {
        self.order = order
        var offsets: [TimeInterval] = []
        offsets.reserveCapacity(order.count)
        var running: TimeInterval = .zero
        for index in order {
            offsets.append(running)
            running += slotLengths[index]
        }
        self.startOffsets = offsets
    }

    /// Binary search for the slot whose start is the last one `<= offset`.
    func slot(containing offset: TimeInterval) -> Int {
        var low = 0
        var high = startOffsets.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if startOffsets[mid] <= offset {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }
}
