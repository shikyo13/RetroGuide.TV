import Foundation
import Testing
@testable import RetroGuideKit

@Suite("Playback preparation")
struct PlaybackPreparationTests {
    private func clients() -> [any MediaServerClient] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlaybackFixtureProtocol.self]
        let http = HTTPClient(session: URLSession(configuration: configuration))
        let base = URL(string: "https://playback.invalid")!
        return [
            PlexServerClient(serverID: "plex", baseURL: base, token: "fixture",
                identity: PlexClientIdentity(clientIdentifier: "fixture", product: "RetroGuide.TV", version: "1.5",
                    platform: "macOS", platformVersion: "test", device: "Mac", deviceName: "Test"), http: http, playbackHTTP: http),
            JellyfinServerClient(serverID: "jellyfin", baseURL: base, token: "fixture", userID: "user",
                identity: JellyfinClientIdentity(deviceID: "fixture", deviceName: "Test", client: "RetroGuide.TV", version: "1.5"),
                http: http, playbackHTTP: http),
        ]
    }

    @Test("A discarded first clip cannot supply the full movie's audio and subtitles")
    func retainedVersionTracksMatchPlayback() async throws {
        let versions = [
            MediaVersion(index: 0, container: "mkv", videoCodec: "h264", audioCodec: "aac", filePath: "/clip", duration: 71),
            MediaVersion(index: 1, container: "mkv", videoCodec: "h264", audioCodec: "aac", filePath: "/full", duration: 5393),
        ]
        let retained = FullLengthVersions.select(versions, reported: 71)
        #expect(retained.versions.map(\.index) == [1])
        for client in clients() {
            let item = MediaItem(serverID: client.serverID, itemKey: "movie", libraryID: "movies", kind: .movie,
                title: "Movie", duration: retained.duration!, versions: retained.versions)
            let playback = try await client.preparePlayback(for: item, startingAt: 600, capabilities: .universal, preferences: nil)
            #expect(playback.request.versionIndex == 1)
            #expect(playback.tracks?.selection.audioStreamIndex == 2)
            #expect(playback.tracks?.selection.subtitle == .embedded(streamIndex: 3))
            #expect(playback.tracks?.subtitles.count == 1)
        }
    }

    @Test("Jellyfin OnlyForced configuration suppresses ordinary subtitles selected by the server")
    func onlyForcedSurvivesAccountAndTrackMapping() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlaybackFixtureProtocol.self]
        let http = HTTPClient(session: URLSession(configuration: configuration))
        let identity = JellyfinClientIdentity(deviceID: "fixture", deviceName: "Test", client: "RetroGuide.TV", version: "1.5")
        let preferences = try await JellyfinAccountService(identity: identity, http: http)
            .languagePreferences(baseURL: URL(string: "https://playback.invalid")!, token: "fixture")
        #expect(preferences.subtitleMode == .forcedOnly)
        let client = clients()[1]
        let item = MediaItem(serverID: client.serverID, itemKey: "movie", libraryID: "movies", kind: .movie,
            title: "Movie", duration: 5393, versions: [
                MediaVersion(index: 1, container: "mkv", videoCodec: "h264", audioCodec: "aac", filePath: "/full", duration: 5393),
            ])
        let playback = try await client.preparePlayback(for: item, startingAt: 600, capabilities: .universal, preferences: preferences)
        #expect(playback.tracks?.selection.audioStreamIndex == 2)
        #expect(playback.tracks?.selection.subtitle == SubtitleChoice.none)
    }
}

private final class PlaybackFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let payload: String
        if request.url!.path.contains("Users/Me") {
            payload = #"{"Id":"user","Configuration":{"SubtitleMode":"OnlyForced","SubtitleLanguagePreference":"eng"}}"#
        } else if request.url!.path.contains("PlaybackInfo") {
            payload = #"{"MediaSources":[{"Id":"/clip","DefaultAudioStreamIndex":1,"MediaStreams":[{"Type":"Audio","Index":1,"Language":"eng"}]},{"Id":"/full","DefaultAudioStreamIndex":2,"DefaultSubtitleStreamIndex":3,"MediaStreams":[{"Type":"Audio","Index":2,"Language":"jpn"},{"Type":"Subtitle","Index":3,"Language":"eng","Codec":"subrip"}]}]}"#
        } else if request.url!.path.contains("decision") {
            payload = #"{"MediaContainer":{"generalDecisionCode":1000,"Metadata":[{"Media":[{"Part":[{"key":"/full"}]}]}]}}"#
        } else {
            payload = #"{"MediaContainer":{"Metadata":[{"ratingKey":"movie","title":"Movie","Media":[{"Part":[{"Stream":[{"streamType":2,"index":1,"languageCode":"eng","selected":true}]}]},{"Part":[{"Stream":[{"streamType":2,"index":2,"languageCode":"jpn","selected":true},{"streamType":3,"index":3,"languageCode":"eng","selected":true}]}]}]}]}}"#
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
