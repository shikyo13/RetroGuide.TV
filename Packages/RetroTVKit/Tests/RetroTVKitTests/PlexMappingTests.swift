import Foundation
import Testing
@testable import RetroTVKit

@Suite("Plex mapping")
struct PlexMappingTests {
    private let library = MediaLibrary(serverID: "server", key: "2", title: "TV Shows", kind: .shows)

    private func loadFixture() throws -> [PlexMetadata] {
        let url = try #require(Bundle.module.url(forResource: "plex-episodes", withExtension: "json", subdirectory: "Fixtures"))
        let envelope = try JSONDecoder().decode(PlexEnvelope<PlexMetadataPage>.self, from: Data(contentsOf: url))
        return envelope.mediaContainer.metadata ?? []
    }

    @Test("Episodes map with series info, full tag memberships and artwork")
    func mapsEpisode() throws {
        let metadata = try loadFixture()
        var memberships = PlexTagMemberships()
        memberships.genres["900"] = ["Comedy", "Family"]
        memberships.networks["900"] = ["NBC"]

        let item = try #require(PlexItemMapper.episode(metadata[0], show: nil, library: library, memberships: memberships))
        #expect(item.id == "server/1001")
        #expect(item.kind == .episode)
        #expect(item.series?.title == "Example Show")
        #expect(item.series?.episodeCode == "S1 E1")
        #expect(item.duration == 1_320)
        #expect(item.genres == ["Comedy", "Family"])
        #expect(item.networks == ["NBC"])
        #expect(item.audience == .family)
        #expect(item.artwork.logo == "/library/metadata/900/clearLogo/1")
        #expect(item.subheadline == "S1 E1 · Pilot")
    }

    @Test("Items without a duration are skipped")
    func skipsUntimed() throws {
        let metadata = try loadFixture()
        #expect(PlexItemMapper.episode(metadata[1], show: nil, library: library, memberships: PlexTagMemberships()) == nil)
    }
}

@Suite("DirectPlayPolicy")
struct DirectPlayPolicyTests {
    private func info(_ container: String, _ video: String, _ audio: String?) -> PlaybackInfo {
        PlaybackInfo(container: container, videoCodec: video, audioCodec: audio, filePath: "/library/parts/1/file")
    }

    @Test("MP4 with Apple-supported codecs plays directly")
    func directPlayable() {
        #expect(DirectPlayPolicy.canDirectPlay(info("mp4", "h264", "aac")))
        #expect(DirectPlayPolicy.canDirectPlay(info("MOV", "hevc", "eac3")))
    }

    @Test("MKV, AVI and unsupported codecs need the server")
    func needsServer() {
        #expect(!DirectPlayPolicy.canDirectPlay(info("mkv", "h264", "aac")))
        #expect(!DirectPlayPolicy.canDirectPlay(info("avi", "mpeg4", "mp3")))
        #expect(!DirectPlayPolicy.canDirectPlay(info("mp4", "h264", "dca")))
        #expect(!DirectPlayPolicy.canDirectPlay(nil))
    }
}

@Suite("PlaybackCapabilities")
struct PlaybackCapabilitiesTests {
    @Test("A universal player direct plays any file with a path")
    func universalPlaysAnything() {
        let mkv = PlaybackInfo(container: "mkv", videoCodec: "hevc", audioCodec: "dca", filePath: "/library/parts/1/file.mkv")
        #expect(DirectPlayPolicy.canDirectPlay(mkv, with: .universal))
        #expect(!DirectPlayPolicy.canDirectPlay(mkv, with: .appleNative))
        let pathless = PlaybackInfo(container: "mkv", videoCodec: "h264", audioCodec: "aac", filePath: nil)
        #expect(!DirectPlayPolicy.canDirectPlay(pathless, with: .universal))
    }
}
