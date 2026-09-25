import Foundation

/// One airing of an item on a channel.
public struct ScheduledProgram: Sendable, Hashable, Identifiable {
    public let channelID: String
    public let item: MediaItem
    /// When the program begins.
    public let start: Date
    /// When the program's content ends.
    public let contentEnd: Date
    /// When the next program begins (equal to `contentEnd` unless the grid adds an intermission).
    public let slotEnd: Date
    let cycle: Int
    let slot: Int

    public var id: String {
        "\(channelID)#\(cycle)#\(slot)"
    }

    public var slotInterval: DateInterval {
        DateInterval(start: start, end: slotEnd)
    }

    /// Seconds into the program at `date`, clamped to the content length.
    public func elapsed(at date: Date) -> TimeInterval {
        min(max(date.timeIntervalSince(start), .zero), item.duration)
    }

    /// Fraction of the slot that has aired at `date`, in `0...1`.
    public func progress(at date: Date) -> Double {
        let length = slotEnd.timeIntervalSince(start)
        guard length > .zero else { return .zero }
        return min(max(date.timeIntervalSince(start) / length, .zero), 1)
    }

    /// Whether `date` falls in the intermission after the content has finished.
    public func isInIntermission(at date: Date) -> Bool {
        date >= contentEnd && date < slotEnd
    }

    public func contains(_ date: Date) -> Bool {
        date >= start && date < slotEnd
    }
}
