import Foundation
import Testing
@testable import RetroGuideKit

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
    private func info(_ container: String, _ video: String, _ audio: String?) -> MediaVersion {
        MediaVersion(container: container, videoCodec: video, audioCodec: audio, filePath: "/library/parts/1/file")
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
        let mkv = MediaVersion(container: "mkv", videoCodec: "hevc", audioCodec: "dca", filePath: "/library/parts/1/file.mkv")
        #expect(DirectPlayPolicy.canDirectPlay(mkv, with: .universal))
        #expect(!DirectPlayPolicy.canDirectPlay(mkv, with: .appleNative))
        let pathless = MediaVersion(container: "mkv", videoCodec: "h264", audioCodec: "aac", filePath: nil)
        #expect(!DirectPlayPolicy.canDirectPlay(pathless, with: .universal))
    }
}

@Suite("Plex track selection")
struct PlexTrackSelectionTests {
    private func stream(_ type: Int, index: Int?, key: String? = nil, selected: Bool?) -> PlexStream {
        PlexStream(streamType: type, index: index, key: key, selected: selected)
    }

    @Test("Selected embedded audio and subtitle streams are used")
    func embedded() {
        let streams = [
            stream(PlexAPI.StreamType.audio, index: 1, selected: true),
            stream(PlexAPI.StreamType.audio, index: 2, selected: nil),
            stream(PlexAPI.StreamType.subtitle, index: 3, selected: true),
        ]
        let selection = PlexTrackSelectionMapper.selection(from: streams, preferences: nil) { _ in nil }
        #expect(selection == TrackSelection(audioStreamIndex: 1, subtitle: .embedded(streamIndex: 3)))
    }

    @Test("No selected subtitle means subtitles off")
    func subtitlesOff() {
        let streams = [stream(PlexAPI.StreamType.audio, index: 1, selected: true), stream(PlexAPI.StreamType.subtitle, index: 2, selected: nil)]
        #expect(PlexTrackSelectionMapper.selection(from: streams, preferences: nil) { _ in nil }.subtitle == .none)
    }

    @Test("Sidecar subtitles resolve to a URL")
    func external() throws {
        let url = try #require(URL(string: "https://server/library/streams/9"))
        let streams = [stream(PlexAPI.StreamType.subtitle, index: nil, key: "/library/streams/9", selected: true)]
        #expect(PlexTrackSelectionMapper.selection(from: streams, preferences: nil) { _ in url }.subtitle == .external(url))
    }
}
