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
        #expect(SubtitleTiming.description(of: 0) == "Original timing")
        #expect(SubtitleTiming.description(of: 0.02) == "Original timing")
        #expect(SubtitleTiming.description(of: 1.5) == "1.5 s later")
        #expect(SubtitleTiming.description(of: -2) == "2 s earlier")
    }

    @Test("Invalid offsets cannot reach the player")
    func nonfinite() {
        #expect(SubtitleTiming.clamped(.nan) == 0)
        #expect(SubtitleTiming.clamped(.infinity) == 0)
        #expect(SubtitleTiming.clamped(-.infinity) == 0)
    }

    @Test("Each subtitle track keeps its own correction, including across off/on")
    func trackTiming() {
        var state = SubtitleTimingState()
        let first = SubtitleChoice.embedded(streamIndex: 2)
        let second = SubtitleChoice.external(URL(string: "https://example.test/subtitle.srt")!)
        state.prepare(itemID: "episode", versionIndex: 0, subtitle: first)
        state.setDelay(1.5)
        state.select(second)
        #expect(state.delay == 0)
        state.setDelay(-2)
        state.select(.none)
        state.setDelay(5)
        #expect(state.delay == 0)
        state.select(first)
        #expect(state.delay == 1.5)
        state.select(second)
        #expect(state.delay == -2)
        state.setDelay(0)
        state.select(first)
        #expect(state.delay == 1.5)
    }

    @Test("Retunes preserve timing; another file or program resets it")
    func playbackTiming() {
        var state = SubtitleTimingState()
        let subtitle = SubtitleChoice.embedded(streamIndex: 2)
        state.prepare(itemID: "episode", versionIndex: 0, subtitle: subtitle)
        state.setDelay(2)
        state.prepare(itemID: "episode", versionIndex: 0, subtitle: subtitle)
        #expect(state.delay == 2)
        state.prepare(itemID: "episode", versionIndex: 1, subtitle: subtitle)
        #expect(state.delay == 0)
        state.setDelay(-3)
        state.prepare(itemID: "next", versionIndex: 1, subtitle: subtitle)
        #expect(state.delay == 0)
    }
}
