import Foundation

/// Channels ordered by when their next program starts (milliseconds; then
/// by position, so the order is deterministic): a binary min-heap.
struct StartQueue {
    private typealias Entry = (start: Int, channel: Int)

    private var heap: [Entry] = []

    init(_ entries: [(Int, Int)]) {
        heap.reserveCapacity(entries.count)
        for (start, channel) in entries {
            push(start, channel)
        }
    }

    var peek: Int? {
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

    mutating func push(_ start: Int, _ channel: Int) {
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
    mutating func replaceTop(_ start: Int) {
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
