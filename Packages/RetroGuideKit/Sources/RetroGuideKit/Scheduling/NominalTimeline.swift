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
