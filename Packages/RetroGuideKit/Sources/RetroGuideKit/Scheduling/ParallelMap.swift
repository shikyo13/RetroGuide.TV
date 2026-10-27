import Foundation

/// Maps independent work across the CPU's cores, keeping the order of results.
enum ParallelMap {
    static func map<T: Sendable>(_ indices: Range<Int>, _ transform: @Sendable (Int) -> T) -> [T] {
        let count = indices.count
        guard count > 1 else { return indices.map(transform) }
        let results = UnsafeMutableBufferPointer<T?>.allocate(capacity: count)
        results.initialize(repeating: nil)
        defer {
            results.deinitialize()
            results.deallocate()
        }
        nonisolated(unsafe) let slots = results
        let lower = indices.lowerBound
        DispatchQueue.concurrentPerform(iterations: count) { offset in
            // Each iteration writes only its own slot.
            slots[offset] = transform(lower + offset)
        }
        return results.map { $0! }
    }
}
