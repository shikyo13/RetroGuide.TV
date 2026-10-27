import Foundation
import Testing
@testable import RetroGuideKit

@Suite("Repeating slot")
struct RepeatingSlotTests {
    /// Airs 10..<20, 110..<120, 210..<220, …
    private let slot = RepeatingSlot(offset: 10, length: 10, period: 100)

    @Test("Overlaps any span touching one of its airings")
    func overlaps() {
        #expect(slot.overlaps(from: 15, to: 16))
        #expect(slot.overlaps(from: 0, to: 11))
        #expect(slot.overlaps(from: 19, to: 50))
        #expect(slot.overlaps(from: 505, to: 515))
        #expect(slot.overlaps(from: 0, to: 1_000))
    }

    @Test("Back to back isn't overlap")
    func edges() {
        #expect(!slot.overlaps(from: 20, to: 110))
        #expect(!slot.overlaps(from: 0, to: 10))
        #expect(!slot.overlaps(from: 220, to: 305))
    }
}
