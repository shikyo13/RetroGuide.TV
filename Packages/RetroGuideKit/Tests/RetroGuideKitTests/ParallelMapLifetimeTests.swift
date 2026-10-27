import Testing
@testable import RetroGuideKit

@Suite("Parallel map lifetimes")
struct ParallelMapLifetimeTests {
    private final class Value: Sendable {}
    private final class WeakValue: @unchecked Sendable {
        weak var value: Value?
    }

    @Test("Temporary result storage releases its references after the returned array is released")
    func releasesResults() {
        let weakValues = (0..<32).map { _ in WeakValue() }
        do {
            let values = ParallelMap.map(weakValues.indices) { index in
                let value = Value()
                weakValues[index].value = value
                return value
            }
            withExtendedLifetime(values) {
                #expect(weakValues.allSatisfy { $0.value != nil })
            }
        }
        #expect(weakValues.allSatisfy { $0.value == nil })
    }
}
