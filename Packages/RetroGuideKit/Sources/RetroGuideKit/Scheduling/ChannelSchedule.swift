import Foundation

/// What's on a channel when: the guide and tuner only need these queries.
public protocol ChannelSchedule: AnyObject, Sendable {
    var channelID: String { get }
    var isEmpty: Bool { get }
    /// The program airing at `date`.
    func program(at date: Date) -> ScheduledProgram?
    /// The program that follows `program` on this channel.
    func program(after program: ScheduledProgram) -> ScheduledProgram?
}

extension ChannelSchedule {
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
}

extension ChannelTimeline: ChannelSchedule {}
