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

    @Test("The next episode starts with the show's correction; other shows and movies don't")
    func showTiming() {
        var state = SubtitleTimingState()
        // Each episode has its own stream numbering.
        state.prepare(itemID: "s1e1", versionIndex: 0, show: "show", subtitle: .embedded(streamIndex: 2))
        state.setDelay(1.5)
        state.prepare(itemID: "s1e2", versionIndex: 0, show: "show", subtitle: .embedded(streamIndex: 3))
        #expect(state.delay == 1.5)
        state.prepare(itemID: "other", versionIndex: 0, show: "other show", subtitle: .embedded(streamIndex: 2))
        #expect(state.delay == 0)
        state.prepare(itemID: "movie", versionIndex: 0, show: nil, subtitle: .embedded(streamIndex: 2))
        #expect(state.delay == 0)
        // Subtitles turned on partway through an episode still get the correction.
        state.prepare(itemID: "s1e3", versionIndex: 0, show: "show", subtitle: .none)
        #expect(state.delay == 0)
        state.select(.embedded(streamIndex: 4))
        #expect(state.delay == 1.5)
    }

    @Test("Setting an episode back to original timing forgets the show's correction")
    func showReset() {
        var state = SubtitleTimingState()
        let subtitle = SubtitleChoice.embedded(streamIndex: 2)
        state.prepare(itemID: "s1e1", versionIndex: 0, show: "show", subtitle: subtitle)
        state.setDelay(2)
        state.prepare(itemID: "s1e2", versionIndex: 0, show: "show", subtitle: subtitle)
        state.setDelay(0)
        #expect(state.delay == 0)
        state.prepare(itemID: "s1e3", versionIndex: 0, show: "show", subtitle: subtitle)
        #expect(state.delay == 0)
    }

    @Test("Show corrections survive saving and stay bounded")
    func showOffsetsStorage() throws {
        var offsets = ShowSubtitleOffsets()
        for index in 0...ShowSubtitleOffsets.capacity {
            offsets.set(1, for: "show \(index)")
        }
        #expect(offsets.count == ShowSubtitleOffsets.capacity)
        #expect(offsets["show 0"] == nil)
        // Adjusting a show again keeps it among the remembered ones.
        offsets.set(-2, for: "show 1")
        offsets.set(1, for: "one more")
        #expect(offsets["show 1"] == -2)
        let saved = try JSONDecoder().decode(ShowSubtitleOffsets.self, from: JSONEncoder().encode(offsets))
        var state = SubtitleTimingState()
        state.restore(saved)
        state.prepare(itemID: "episode", versionIndex: 0, show: "show 1", subtitle: .embedded(streamIndex: 2))
        #expect(state.delay == -2)
    }
}
