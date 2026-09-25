import Foundation

extension Sequence where Element: Sendable {
    /// Maps elements concurrently with at most `limit` tasks in flight,
    /// preserving input order in the result.
    func concurrentMap<T: Sendable>(
        limit: Int,
        _ transform: @escaping @Sendable (Element) async throws -> T
    ) async throws -> [T] {
        let elements = Array(self)
        guard !elements.isEmpty else { return [] }
        return try await withThrowingTaskGroup(of: (Int, T).self) { group in
            var results = [T?](repeating: nil, count: elements.count)
            var nextIndex = 0
            func enqueueNext() {
                guard nextIndex < elements.count else { return }
                let index = nextIndex
                let element = elements[index]
                group.addTask { (index, try await transform(element)) }
                nextIndex += 1
            }
            for _ in 0..<Swift.min(limit, elements.count) {
                enqueueNext()
            }
            while let (index, value) = try await group.next() {
                results[index] = value
                enqueueNext()
            }
            return results.compactMap { $0 }
        }
    }
}
