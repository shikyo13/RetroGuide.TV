import Foundation

/// A channel scheduled on its own (hidden channels, and custom ones outside
/// the shared lineup): with nothing to steer around it airs its
/// ``NominalOrder`` exactly, so any moment is found by arithmetic. The order
/// is worked out on first use: hidden channels may never be asked.
final class NominalTimeline: ChannelSchedule, @unchecked Sendable {
    let channelID: String
    private let context: ScheduleContext
    private let ordering: ScheduleOrdering
    private let lock = NSLock()
    private var built: (any NominalOrder)?

    init(context: ScheduleContext, ordering: ScheduleOrdering) {
        channelID = context.channelID
        self.context = context
        self.ordering = ordering
    }

    var isEmpty: Bool {
        context.isEmpty
    }

    func program(at date: Date) -> ScheduledProgram? {
        let offset = ScheduleTime.milliseconds(since: date)
        guard !isEmpty, offset >= .zero else { return nil }
        let order = order()
        return program(position: order.position(at: offset), in: order)
    }

    func program(after program: ScheduledProgram) -> ScheduledProgram? {
        guard !isEmpty else { return nil }
        return self.program(position: program.slot + 1, in: order())
    }

    /// The channel's items, as ``forEachAiring(from:to:_:)`` numbers them.
    var items: [MediaItem] {
        context.items
    }

    /// Every program from `begin` to `end` (milliseconds since the epoch) as
    /// the index of the item it airs and its slot, without building programs:
    /// for channels others steer around (``SimulcastCoordinator``).
    func forEachAiring(from begin: Int, to end: Int, _ body: (_ item: Int, _ start: Int, _ end: Int) -> Void) {
        let from = max(begin, .zero)
        guard !isEmpty, end > from else { return }
        let order = order()
        var position = order.position(at: from)
        var start = order.start(of: position)
        // Programs run back to back, so each one starts where the last ended.
        while start < end {
            let item = order.program(at: position).item
            let slotEnd = start + context.slotLengths[item]
            body(item, start, slotEnd)
            start = slotEnd
            position += 1
        }
    }

    private func order() -> any NominalOrder {
        lock.lock()
        defer { lock.unlock() }
        if let built {
            return built
        }
        let order = NominalOrders.make(ordering: ordering, context: context)
        built = order
        return order
    }

    /// The program at `position` of the order (kept as the program's slot).
    private func program(position: Int, in order: any NominalOrder) -> ScheduledProgram {
        context.program(item: order.program(at: position).item, start: order.start(of: position), cycle: .zero, slot: position)
    }
}
