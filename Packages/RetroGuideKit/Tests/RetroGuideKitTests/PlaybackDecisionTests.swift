import Foundation
import Testing
@testable import RetroGuideKit

struct PlaybackDecisionTests {
    private func decision(_ json: String) throws -> PlexPlaybackDecision {
        try JSONDecoder().decode(PlexEnvelope<PlexDecisionContainer>.self, from: Data(json.utf8)).mediaContainer.decision
    }

    @Test func directPlayOKReturnsTheAuthorizedPart() throws {
        let json = """
        {"MediaContainer":{"generalDecisionCode":1000,"Metadata":[{"Media":[{"Part":[{"key":"/library/parts/42022/1788565070/file.mkv"}]}]}]}}
        """
        #expect(try decision(json) == .directPlay(partKey: "/library/parts/42022/1788565070/file.mkv"))
    }

    @Test func aDeletedFileIsUnavailable() throws {
        let json = """
        {"MediaContainer":{"generalDecisionCode":2000,"generalDecisionText":"Neither direct play nor conversion is available."}}
        """
        #expect(try decision(json) == .unavailable)
    }
}

struct VersionRankingTests {
    private let remux4K = MediaVersion(index: 0, container: "mkv", videoCodec: "hevc", audioCodec: "truehd", filePath: "/a", height: 2160, bitrateKbps: 70_000)
    private let bluray4K = MediaVersion(index: 1, container: "mkv", videoCodec: "hevc", audioCodec: "eac3", filePath: "/b", height: 2160, bitrateKbps: 19_000)
    private let bluray1080 = MediaVersion(index: 2, container: "mkv", videoCodec: "h264", audioCodec: "eac3", filePath: "/c", height: 1080, bitrateKbps: 10_000)

    @Test func originalFallsBackFromTheBestCopyToSmallerOnes() {
        let ranked = MediaVersionSelector.ranked([bluray1080, remux4K, bluray4K], for: .original)
        #expect(ranked.map(\.index) == [0, 1, 2])
    }

    @Test func aLimitPrefersCopiesWithinItThenTheSmallestAboveIt() {
        let ranked = MediaVersionSelector.ranked([remux4K, bluray1080, bluray4K], for: .upTo1080p)
        #expect(ranked.map(\.index) == [2, 1, 0])
    }

    @Test func bestIsTheFirstRankedCopy() {
        #expect(MediaVersionSelector.best(of: [bluray1080, remux4K], for: .original)?.index == 0)
    }
}
