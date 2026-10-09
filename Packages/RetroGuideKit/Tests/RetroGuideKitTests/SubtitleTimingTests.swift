import Foundation
import Testing
@testable import RetroGuideKit

@Suite("SubtitleTiming")
struct SubtitleTimingTests {
    @Test("Delays stay within range at tenth-of-a-second precision")
    func clamping() {
        #expect(SubtitleTiming.clamped(45) == 30)
        #expect(SubtitleTiming.clamped(-45) == -30)
        #expect(abs(SubtitleTiming.clamped(1.234) - 1.2) < 0.0001)
        #expect(abs(SubtitleTiming.clamped(-0.06) - -0.1) < 0.0001)
    }

    @Test("Held buttons speed up and stay at the top step")
    func acceleration() {
        #expect(SubtitleTiming.step(forRepeat: 0) == 0.1)
        #expect(SubtitleTiming.step(forRepeat: 3) == 0.5)
        #expect(SubtitleTiming.step(forRepeat: 99) == 1)
    }

    @Test("Descriptions say which way subtitles moved")
    func descriptions() {
        #expect(SubtitleTiming.description(of: 0) == "In sync")
        #expect(SubtitleTiming.description(of: 0.02) == "In sync")
        #expect(SubtitleTiming.description(of: 1.5) == "1.5 s later")
        #expect(SubtitleTiming.description(of: -2) == "2 s earlier")
    }
}
