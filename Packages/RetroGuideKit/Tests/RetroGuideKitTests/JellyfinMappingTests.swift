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

    @Test("An episode's premiere date becomes its release date")
    func mapsPremiereDate() throws {
        let fixture = try fixture()
        // Jellyfin sends PremiereDate with every item (it isn't one of the requestable Fields).
        let url = try #require(Bundle.module.url(forResource: "jellyfin-episode", withExtension: "json", subdirectory: "Fixtures"))
        let raw = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var json = try #require(raw["Episode"] as? [String: Any])
        json["PremiereDate"] = "2008-08-06T00:00:00.0000000Z"
        let episode = try JellyfinCoding.decoder.decode(JellyfinItem.self, from: JSONSerialization.data(withJSONObject: json))
        let networks = JellyfinNetworks(shows: [fixture.series]).networks(of: fixture.series)
        let item = try #require(JellyfinItemMapper.episode(episode, series: fixture.series, networks: networks, library: library, collections: [:]))
        #expect(item.released == ISO8601DateFormatter().date(from: "2008-08-06T00:00:00Z"))
    }

    private func tried(_ text: String) -> [String] {
        JellyfinAddress.candidates(from: JellyfinAddress.upgradingInsecureScheme(text)).map(\.absoluteString)
    }

    @Test("A typed address becomes the URLs worth trying")
    func addressCandidates() {
        #expect(tried("10.0.1.5") == ["https://10.0.1.5", "https://10.0.1.5:8920", "https://10.0.1.5:8096"])
        // An http:// address is never tried as typed, only over HTTPS at the same place.
        #expect(tried("http://10.0.1.5:8096") == ["https://10.0.1.5:8096"])
        #expect(tried(" media.example.com:8920 ") == ["https://media.example.com:8920"])
        #expect(tried("  ").isEmpty)
        #expect(JellyfinAddress.candidates(from: "http://10.0.1.5:8096").isEmpty)
    }

    @Test("A scheme without a port tries the same ports as a bare address")
    func schemeWithoutPort() {
        #expect(tried("http://10.0.1.5") == tried("10.0.1.5"))
        #expect(tried("https://media.example.com") == tried("media.example.com"))
    }

    @Test("An address copied from the browser finds the server behind the page")
    func browserAddress() {
        let server = ["https://10.0.1.5:8096"]
        // The root first; a server that really lives at /web is tried after it.
        let pastedWeb = server + ["https://10.0.1.5:8096/web"]
        #expect(tried("http://10.0.1.5:8096/web/#/home.html") == pastedWeb)
        #expect(tried("http://10.0.1.5:8096/web/index.html#!/home.html") == server)
        #expect(tried("10.0.1.5:8096/web/") == pastedWeb)
        // A server under its own path keeps it.
        #expect(tried("https://example.com:8920/jellyfin/web/index.html") == ["https://example.com:8920/jellyfin", "https://example.com:8920"])
        #expect(JellyfinAddress.plainHTTP(from: "http://10.0.1.5:8096/web/index.html")?.absoluteString == "http://10.0.1.5:8096")
    }

    @Test("A server's own path survives as typed: spaces, escaped slashes, a base at /web")
    func unusualServerPaths() {
        #expect(tried("https://media.example.com:8920/TV 2024").first == "https://media.example.com:8920/TV%202024")
        #expect(tried("https://media.example.com:8920/a%2Fb").first == "https://media.example.com:8920/a%2Fb")
        #expect(tried("https://media.example.com:8920/web").contains("https://media.example.com:8920/web"))
        // A loosely typed port is still repaired in the host part.
        #expect(tried("10.0.1.5 8096").first == "https://10.0.1.5:8096")
        #expect(JellyfinAddress.plainHTTP(from: "http://10.0.1.5:8096/a%2Fb")?.absoluteString == "http://10.0.1.5:8096/a%2Fb")
    }

    @Test("A path that may not be the server's is tried first, then the address without it")
    func pathFallsBackToRoot() {
        #expect(tried("https://example.com/jellyfin/") == [
            "https://example.com/jellyfin", "https://example.com:8920/jellyfin", "https://example.com:8096/jellyfin",
            "https://example.com", "https://example.com:8920", "https://example.com:8096",
        ])
    }

    @Test("A port typed after a space, comma or semicolon still counts")
    func loosePort() {
        let server = ["https://10.0.1.5:8096"]
        #expect(tried("10.0.1.5 8096") == server)
        #expect(tried("10.0.1.5,8096") == server)
        #expect(tried("10.0.1.5; 8096") == server)
        #expect(tried(" 10.0.1.5 :8096 ") == server)
        #expect(tried("http://10.0.1.5 8096") == server)
        #expect(JellyfinAddress.plainHTTP(from: "10.0.1.5 8096")?.absoluteString == "http://10.0.1.5:8096")
        // Not a port: left as typed.
        #expect(tried("10.0.1.5") == ["https://10.0.1.5", "https://10.0.1.5:8920", "https://10.0.1.5:8096"])
        #expect(tried("[fe80::1]:8096") == ["https://[fe80::1]:8096"])
    }
}
