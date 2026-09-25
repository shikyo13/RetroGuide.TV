import Testing
@testable import RetroGuideKit

struct DisplayMatchingTests {
    private let filmRate = 23.976
    private var sdrFilm: VideoFormat { VideoFormat(dynamicRange: .sdr, frameRate: filmRate) }
    private var hdrFilm: VideoFormat { VideoFormat(dynamicRange: .hdr10, frameRate: filmRate) }

    @Test func offNeverRequestsAMode() {
        #expect(DisplayMatching.off.request(for: hdrFilm) == nil)
        #expect(DisplayMatching.off.request(for: sdrFilm) == nil)
    }

    @Test func dynamicRangeSwitchesOnlyForHDRAndKeepsTheRefreshRate() {
        #expect(DisplayMatching.dynamicRange.request(for: sdrFilm) == nil)
        #expect(DisplayMatching.dynamicRange.request(for: hdrFilm) == DisplayModeRequest(dynamicRange: .hdr10, refreshRate: nil))
        let hlg = VideoFormat(dynamicRange: .hlg, frameRate: nil)
        #expect(DisplayMatching.dynamicRange.request(for: hlg) == DisplayModeRequest(dynamicRange: .hlg, refreshRate: nil))
    }

    @Test func frameRateMatchingAlsoAppliesToStandardRange() {
        let request = DisplayMatching.dynamicRangeAndFrameRate.request(for: sdrFilm)
        #expect(request == DisplayModeRequest(dynamicRange: .sdr, refreshRate: filmRate))
    }

    @Test func unknownFrameRateKeepsTheCurrentRate() {
        let format = VideoFormat(dynamicRange: .hdr10, frameRate: nil)
        #expect(DisplayMatching.dynamicRangeAndFrameRate.request(for: format)?.refreshRate == nil)
    }

    @Test func nothingPlayingUsesTheUsualMode() {
        for matching in DisplayMatching.allCases {
            #expect(matching.request(for: nil) == nil)
        }
    }
}
