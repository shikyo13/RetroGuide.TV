import Foundation

/// A slot that airs every `period` seconds from the epoch, starting `offset`
/// seconds into each period: where an episode sits on a 24/7 channel, whose
/// cycle never changes. Checking it against a span is plain arithmetic, so
/// other channels can steer clear without simulating it.
struct RepeatingSlot: Sendable {
    let offset: TimeInterval
    let length: TimeInterval
    let period: TimeInterval

    /// Whether any airing of the slot overlaps `start..<end` (seconds since the epoch).
    func overlaps(from start: TimeInterval, to end: TimeInterval) -> Bool {
        // The latest airing starting before `end` is the only one that can
        // reach past `start`: airings never overlap each other.
        var cycle = ((end - offset) / period).rounded(.down)
        if offset + cycle * period >= end {
            cycle -= 1
        }
        return offset + cycle * period + length > start
    }
}
