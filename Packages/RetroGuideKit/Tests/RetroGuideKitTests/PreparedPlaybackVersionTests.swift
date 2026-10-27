import Foundation
import Testing
@testable import RetroGuideKit

@Suite("Prepared playback version changes")
struct PreparedPlaybackVersionTests {
    @Test(arguments: [[Int](), [1], [0, 1]])
    func tracksAlwaysFollowTheReturnedStream(versions: [Int]) async throws {
        let client = VersionClient()
        let item = MediaItem(serverID: client.serverID, itemKey: "movie", libraryID: "movies", kind: .movie,
            title: "Movie", duration: 3600, versions: versions.map {
                MediaVersion(index: $0, container: "mkv", videoCodec: "h264", audioCodec: "aac", filePath: "/copy-\($0)")
            })
        let playback = try await client.preparePlayback(for: item, startingAt: 60, capabilities: .universal, preferences: nil)
        #expect(playback.request.versionIndex == 2)
        #expect(playback.tracks?.selection.audioStreamIndex == 2)
        let calls = await client.calls.versions
        #expect(calls.compactMap { $0 }.sorted() == (versions.count == 1 ? [1, 2] : [2]))
        #expect(!calls.contains(nil))
    }
}

private actor TrackCalls {
    var versions: [Int?] = []
    func record(_ version: Int?) { versions.append(version) }
}

private struct VersionClient: MediaServerClient {
    let serverID = "fixture"
    let calls = TrackCalls()
    func streamRequest(for item: MediaItem, startingAt position: TimeInterval, capabilities: PlaybackCapabilities) async throws -> StreamRequest {
        StreamRequest(url: URL(string: "https://fixture.invalid/copy-2")!, startPosition: position,
            startsAtPosition: false, sessionID: "fixture", method: .directPlay, versionIndex: 2)
    }
    func tracks(for item: MediaItem, version: Int?, preferences: LanguagePreferences?) async -> ItemTracks? {
        await calls.record(version)
        return ItemTracks(audio: [], subtitles: [], selection: TrackSelection(audioStreamIndex: version, subtitle: .none))
    }
    func isReachable() async -> Bool { true }
    func fetchLibraries() async throws -> [MediaLibrary] { [] }
    func fetchItems(in libraries: [MediaLibrary], progress: @escaping @Sendable (LibraryLoadProgress) -> Void) async throws -> [MediaItem] { [] }
    func saveTracks(for item: MediaItem, preferences: LanguagePreferences?, choose: @Sendable (ItemTracks, TrackSelection) -> TrackSelection) async -> Bool { false }
    func endStream(sessionID: String) async {}
    func imageURL(for reference: String, size: ImageSize) -> URL? { nil }
}
