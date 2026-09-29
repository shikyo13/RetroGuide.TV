import Foundation

/// Page and cache sizes for ``SimulatedTimeline``.
enum SimulatedTimelineTuning {
    static let programsPerPage = 256
    static let cachedPages = 4
    static let cachedCheckpoints = 8
}

/// A channel schedule computed by running its ``ChannelPicker`` forward from
/// ``ScheduleConstants/epoch``, so every device computes the same guide.
/// Pages of programs are cached along with the picker state to continue from.
/// Used for channels scheduled on their own (no simulcast limit, 24/7 and
/// custom channels); the rest share a ``SimulcastCoordinator``.
final class SimulatedTimeline: ChannelSchedule, @unchecked Sendable {
    private typealias Tuning = SimulatedTimelineTuning

    let channelID: String
    private let context: ScheduleContext
    private let initial: ChannelPicker

    private let lock = NSLock()
    /// Start offset (from the epoch) of every simulated page.
    private var pageStarts: [TimeInterval] = []
    private var checkpoints: [Int: Checkpoint] = [:]
    private var pages: [Int: Page] = [:]
    private var pageRecency: [Int] = []

    private struct Checkpoint {
        var picker: ChannelPicker
        var offset: TimeInterval
    }

    init(channelID: String, context: ScheduleContext, picker: ChannelPicker) {
        self.channelID = channelID
        self.context = context
        self.initial = picker
    }

    var isEmpty: Bool {
        context.isEmpty
    }

    func program(at date: Date) -> ScheduledProgram? {
        guard !isEmpty else { return nil }
        let offset = date.timeIntervalSince(ScheduleConstants.epoch)
        guard offset >= .zero else { return nil }
        lock.lock()
        defer { lock.unlock() }
        let number = page(containing: offset)
        let page = page(number)
        return makeProgram(page: number, slot: page.slot(containing: offset), in: page)
    }

    func program(after program: ScheduledProgram) -> ScheduledProgram? {
        guard !isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        let current = page(program.cycle)
        if program.slot + 1 < current.order.count {
            return makeProgram(page: program.cycle, slot: program.slot + 1, in: current)
        }
        return makeProgram(page: program.cycle + 1, slot: .zero, in: page(program.cycle + 1))
    }

    private func makeProgram(page number: Int, slot: Int, in page: Page) -> ScheduledProgram {
        let index = page.order[slot]
        let item = context.items[index]
        let start = ScheduleConstants.epoch.addingTimeInterval(page.starts[slot])
        return ScheduledProgram(
            channelID: channelID,
            item: item,
            start: start,
            contentEnd: start.addingTimeInterval(item.duration),
            slotEnd: start.addingTimeInterval(context.slotLengths[index]),
            cycle: number,
            slot: slot
        )
    }

    // MARK: - Pages

    private struct Page {
        let order: [Int]
        let starts: [TimeInterval]

        func slot(containing offset: TimeInterval) -> Int {
            var low = 0
            var high = starts.count - 1
            while low < high {
                let mid = (low + high + 1) / 2
                if starts[mid] <= offset { low = mid } else { high = mid - 1 }
            }
            return low
        }
    }

    private func page(containing offset: TimeInterval) -> Int {
        while pageStarts.isEmpty || (pageStarts.last ?? .zero) <= offset {
            _ = page(pageStarts.count)
        }
        var low = 0
        var high = pageStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if pageStarts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }

    private func page(_ number: Int) -> Page {
        if let cached = pages[number] {
            return cached
        }
        let start = checkpoints.keys.filter { $0 <= number }.max()
        var state = start.flatMap { checkpoints[$0] } ?? Checkpoint(picker: initial, offset: .zero)
        var current = start ?? 0
        var built: Page?
        while current <= number {
            if checkpoints[current] == nil {
                checkpoints[current] = state
                trimCheckpoints(keeping: number)
            }
            if current == pageStarts.count {
                pageStarts.append(state.offset)
            }
            let page = simulatePage(&state)
            if current == number {
                built = page
            }
            current += 1
        }
        if checkpoints[current] == nil {
            checkpoints[current] = state
        }
        if current == pageStarts.count {
            pageStarts.append(state.offset)
        }
        let result = built ?? Page(order: [], starts: [])
        pages[number] = result
        pageRecency.removeAll { $0 == number }
        pageRecency.append(number)
        while pageRecency.count > Tuning.cachedPages {
            pages[pageRecency.removeFirst()] = nil
        }
        return result
    }

    private func trimCheckpoints(keeping number: Int) {
        guard checkpoints.count > Tuning.cachedCheckpoints else { return }
        let keep = Set(checkpoints.keys.sorted { abs($0 - number) < abs($1 - number) }.prefix(Tuning.cachedCheckpoints - 1)).union([0])
        checkpoints = checkpoints.filter { keep.contains($0.key) }
    }

    private func simulatePage(_ state: inout Checkpoint) -> Page {
        var order: [Int] = []
        var starts: [TimeInterval] = []
        order.reserveCapacity(Tuning.programsPerPage)
        starts.reserveCapacity(Tuning.programsPerPage)
        while order.count < Tuning.programsPerPage {
            let item = state.picker.next(at: state.offset, in: context) { _ in true }
            order.append(item)
            starts.append(state.offset)
            state.offset += context.slotLengths[item]
        }
        return Page(order: order, starts: starts)
    }
}
