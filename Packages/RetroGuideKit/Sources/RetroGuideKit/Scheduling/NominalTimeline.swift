import Foundation

/// A channel scheduled on its own (hidden channels, and custom ones outside
/// the shared lineup): with nothing to steer around it airs its
/// ``NominalOrder`` exactly, so any moment is found by arithmetic.
final class NominalTimeline: ChannelSchedule, @unchecked Sendable {
    let channelID: String
    private let context: ScheduleContext
    private let order: (any NominalOrder)?

    init(context: ScheduleContext, ordering: ScheduleOrdering) {
        channelID = context.channelID
        self.context = context
        order = context.isEmpty ? nil : NominalOrders.make(ordering: ordering, context: context)
    }

    var isEmpty: Bool {
        order == nil
    }

    func program(at date: Date) -> ScheduledProgram? {
        let offset = ScheduleTime.milliseconds(since: date)
        guard let order, offset >= .zero else { return nil }
        return program(position: order.position(at: offset), in: order)
    }

    func program(after program: ScheduledProgram) -> ScheduledProgram? {
        guard let order else { return nil }
        return self.program(position: program.slot + 1, in: order)
    }

    /// The program at `position` of the order (kept as the program's slot).
    private func program(position: Int, in order: any NominalOrder) -> ScheduledProgram {
        context.program(item: order.program(at: position).item, start: order.start(of: position), cycle: .zero, slot: position)
    }
}
