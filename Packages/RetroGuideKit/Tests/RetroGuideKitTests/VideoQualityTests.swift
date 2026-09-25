import Foundation
import Testing
@testable import RetroGuideKit

@Suite("Video quality")
struct VideoQualityTests {
    private let uhd = MediaVersion(index: 0, container: "mkv", videoCodec: "hevc", audioCodec: "eac3", filePath: "/a", height: 2_160, bitrateKbps: 40_000)
    private let fullHD = MediaVersion(index: 1, container: "mkv", videoCodec: "h264", audioCodec: "ac3", filePath: "/b", height: 1_080, bitrateKbps: 10_000)
    private let sd = MediaVersion(index: 2, container: "mp4", videoCodec: "h264", audioCodec: "aac", filePath: "/c", height: 480, bitrateKbps: 1_500)

    @Test("Each preference picks the expected existing copy", arguments: [
        (VideoQuality.original, 0), (.upTo1080p, 1), (.upTo720p, 2), (.smallest, 2),
    ])
    func selection(quality: VideoQuality, expectedIndex: Int) {
        #expect(MediaVersionSelector.best(of: [uhd, fullHD, sd], for: quality)?.index == expectedIndex)
    }

    @Test("When nothing fits the cap, the smallest copy is used")
    func fallsBackToSmallest() {
        #expect(MediaVersionSelector.best(of: [uhd], for: .upTo720p)?.index == 0)
        #expect(MediaVersionSelector.best(of: [uhd, fullHD], for: .upTo720p)?.index == 1)
    }

    @Test("Duplicates within one server keep the copy that fits its quality setting")
    func dedupeByQuality() {
        func movie(_ key: String, _ version: MediaVersion) -> MediaItem {
            MediaItem(serverID: "friend", itemKey: key, externalID: "plex://movie/x", libraryID: "friend/\(key)",
                      kind: .movie, title: "Movie", duration: 5_400, versions: [version])
        }
        let snapshot = LibrarySnapshot(serverID: "friend", serverName: "Friend", libraries: [],
                                       items: [movie("4k", uhd), movie("hd", fullHD)])
        #expect(LibraryIndex(snapshots: [snapshot], quality: ["friend": .upTo1080p]).items.map(\.itemKey) == ["hd"])
        #expect(LibraryIndex(snapshots: [snapshot], quality: ["friend": .original]).items.map(\.itemKey) == ["4k"])
    }

    @Test("Servers saved before playback settings existed get defaults for their location")
    func legacyAccountDecoding() throws {
        func decode(_ url: String) throws -> ServerAccount {
            let json = #"{"id":"s","kind":"plex","name":"S","baseURL":"\#(url)","selectedLibraryIDs":[]}"#
            return try JSONDecoder().decode(ServerAccount.self, from: Data(json.utf8))
        }
        #expect(try decode("https://10-10-1-25.abc123.plex.direct:32400").playback == .local)
        #expect(try decode("http://192.168.1.20:32400").playback == .local)
        #expect(try decode("https://pserv.example.com:443").playback == .remote)
        #expect(try decode("https://136-32-243-210.abc123.plex.direct:64800").playback == .remote)
    }
}
