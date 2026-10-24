import Foundation
import Testing
@testable import RetroGuideKit

@Suite("Jellyfin mapping")
struct JellyfinMappingTests {
    /// A real anime episode: a 4K MKV with a sidecar English subtitle file.
    private struct Fixture: Decodable {
        let episode: JellyfinItem
        let series: JellyfinItem
        let playbackSource: JellyfinMediaSource
    }

    private let library = MediaLibrary(serverID: "server", key: "anime", title: "Anime", kind: .shows)

    private func fixture() throws -> Fixture {
        let url = try #require(Bundle.module.url(forResource: "jellyfin-episode", withExtension: "json", subdirectory: "Fixtures"))
        return try JellyfinCoding.decoder.decode(Fixture.self, from: Data(contentsOf: url))
    }

    @Test("Embedded tracks get container indexes even though Jellyfin numbers sidecar subtitles first")
    func renumbersTracksAroundSidecars() throws {
        let source = try fixture().playbackSource
        // Jellyfin: sidecar subtitle 0, video 1, audio 2. In the file: video 0, audio 1.
        let tracks = JellyfinTrackMapper.tracks(from: source, preferences: nil) { index, format in URL(string: "https://server/sub/\(index).\(format)") }
        #expect(tracks.audio.map(\.source) == [.embedded(streamIndex: 1)])
        #expect(tracks.selection.audioStreamIndex == 1)
        #expect(tracks.subtitles.map(\.source) == [.external(URL(string: "https://server/sub/0.srt")!)])
    }

    @Test("Episodes map with series info, networks, artwork, the show's ids and Japanese origin")
    func mapsEpisode() throws {
        let fixture = try fixture()
        let networks = JellyfinNetworks(shows: [fixture.series]).networks(of: fixture.series)
        let item = try #require(JellyfinItemMapper.episode(
            fixture.episode, series: fixture.series, networks: networks, library: library, collections: [:]
        ))
        #expect(item.series?.episodeCode == "S4 E3")
        #expect(item.series?.externalID?.hasPrefix("tvdb://") == true)
        #expect(item.titleIDs?.tvdb != nil)
        #expect(item.countries == ["Japan"])
        #expect(item.artwork.poster.flatMap(JellyfinImageReference.init(encoded:))?.itemID == fixture.series.id)
        #expect(item.versions.first?.filePath == fixture.episode.mediaSources?.first?.id)
        #expect(item.versions.first?.height == 2160)
        #expect(item.addedAt != nil)
    }

    @Test("Production companies listed after a show's networks are not networks")
    func separatesNetworksFromCompanies() throws {
        func show(_ studios: [String]) -> JellyfinItem {
            try! JellyfinCoding.decoder.decode(JellyfinItem.self, from: Data("""
                {"Id": "\(UUID().uuidString)", "Studios": [\(studios.map { "{\"Name\": \"\($0)\"}" }.joined(separator: ","))]}
                """.utf8))
        }
        let arrested = show(["FOX", "Netflix", "Imagine Television Studios", "20th Century Fox Television"])
        let shows = [arrested, show(["Netflix", "Gaumont"]), show(["CBS", "Chuck Lorre Productions"]), show(["FOX"])]
        #expect(JellyfinNetworks(shows: shows).networks(of: arrested) == ["FOX", "Netflix"])
    }

    @Test("Jellyfin's seven-digit fractional dates parse")
    func parsesDates() {
        let date = JellyfinCoding.date("2020-11-21T02:13:52.6503687Z")
        #expect(date == ISO8601DateFormatter().date(from: "2020-11-21T02:13:52Z"))
    }

    @Test("A typed address becomes the URLs worth trying")
    func addressCandidates() {
        #expect(JellyfinAddress.candidates(from: "10.0.1.5").map(\.absoluteString)
            == ["http://10.0.1.5:8096", "https://10.0.1.5", "http://10.0.1.5"])
        #expect(JellyfinAddress.candidates(from: " media.example.com:8920 ").map(\.absoluteString)
            == ["http://media.example.com:8920", "https://media.example.com:8920"])
        #expect(JellyfinAddress.candidates(from: "https://example.com/jellyfin/").map(\.absoluteString)
            == ["https://example.com/jellyfin"])
        #expect(JellyfinAddress.candidates(from: "  ").isEmpty)
    }
}
