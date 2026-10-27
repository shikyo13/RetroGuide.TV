import Foundation
import Testing
@testable import RetroGuideKit

@Suite("Jellyfin playback and reporting", .serialized)
struct JellyfinPlaybackTests {
    private func client(_ scenario: String) -> JellyfinServerClient {
        JellyfinPlaybackProtocol.log.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [JellyfinPlaybackProtocol.self]
        let http = HTTPClient(session: URLSession(configuration: configuration))
        return JellyfinServerClient(serverID: "server", baseURL: URL(string: "https://\(scenario).invalid/jellyfin")!,
            token: "fixture", userID: "user",
            identity: JellyfinClientIdentity(deviceID: "fixture", deviceName: "Test", client: "RetroGuide.TV", version: "1.5"),
            http: http, playbackHTTP: http)
    }

    private let item = MediaItem(serverID: "server", itemKey: "movie", libraryID: "movies", kind: .movie,
        title: "Two copies", duration: 3600, versions: [
            MediaVersion(index: 4, container: "mp4", videoCodec: "h264", audioCodec: "aac", filePath: "missing", height: 2160),
            MediaVersion(index: 7, container: "mkv", videoCodec: "h264", audioCodec: "aac", filePath: "available", height: 1080),
        ])

    @Test("Missing preferred copy falls back without losing the original version index or proxy prefix")
    func missingCopy() async throws {
        let client = client("fallback")
        let result = try await client.preparePlayback(for: item, startingAt: 123, capabilities: .universal, preferences: nil)
        #expect(result.request.versionIndex == 7)
        #expect(result.request.startPosition == 123)
        #expect(result.request.url.path == "/jellyfin/Videos/movie/stream")
        #expect(result.tracks?.selection.audioStreamIndex == 1)
        #expect(result.tracks?.audio.first?.serverStreamIndex == 2)
        let requests = JellyfinPlaybackProtocol.log.requests.filter { $0.httpMethod == "HEAD" }
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.url?.scheme == "https" })
    }

    @Test("A surviving incompatible copy uses HLS with the same selected version")
    func nativeFallback() async throws {
        let result = try await client("fallback").streamRequest(for: item, startingAt: 123, capabilities: .appleNative)
        #expect(result.versionIndex == 7)
        #expect(result.method == .directStream)
        #expect(result.url.path == "/jellyfin/Videos/movie/master.m3u8")
    }

    @Test("Rejected authentication is not disguised as a missing file")
    func authenticationFailure() async {
        await #expect(throws: HTTPError.unauthorized) {
            try await client("unauthorized").streamRequest(for: item, startingAt: 0, capabilities: .universal)
        }
        #expect(JellyfinPlaybackProtocol.log.requests.count == 1)
    }

    @Test("All missing copies produce the actionable missing-file error")
    func allMissing() async {
        await #expect(throws: StreamError.noPlayableVersion) {
            try await client("missing").streamRequest(for: item, startingAt: 0, capabilities: .universal)
        }
    }

    @Test("An unreachable server stays distinct from missing files")
    func unreachable() async {
        await #expect(throws: StreamError.serverUnreachable) {
            try await client("offline").streamRequest(for: item, startingAt: 0, capabilities: .universal)
        }
    }

    @Test("Cancellation does not try a second copy")
    func cancellation() async {
        let client = client("cancel")
        let task = Task {
            try await client.streamRequest(for: item, startingAt: 0, capabilities: .universal)
        }
        let deadline = ContinuousClock.now + .seconds(5)
        while JellyfinPlaybackProtocol.log.requests.isEmpty, ContinuousClock.now < deadline { await Task.yield() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(JellyfinPlaybackProtocol.log.requests.count == 1)
    }

    @Test("Reports retain Jellyfin indexes for embedded and external tracks and explicit subtitle off")
    func reportedTracks() async throws {
        let client = client("fallback")
        let playback = try await client.preparePlayback(for: item, startingAt: 123, capabilities: .universal, preferences: nil)
        let tracks = try #require(playback.tracks)
        let external = try #require(tracks.subtitles.first { $0.serverStreamIndex == 0 })
        let selections = [tracks.selection,
            TrackSelection(audioStreamIndex: 1, subtitle: external.subtitleChoice),
            TrackSelection(audioStreamIndex: 1, subtitle: .none)]
        for selection in selections {
            #expect(await client.reportPlayback(PlaybackReport(event: .progress, item: item, request: playback.request,
                position: 125.5, isPaused: true, tracks: tracks, selection: selection)))
        }
        let reports = try JellyfinPlaybackProtocol.log.requests.filter { $0.url?.path.hasSuffix("/Progress") == true }.map(body)
        #expect(reports.count == 3)
        #expect(reports.compactMap { $0["AudioStreamIndex"] as? Int } == [2, 2, 2])
        #expect(reports.compactMap { $0["SubtitleStreamIndex"] as? Int } == [3, 0, -1])
        #expect(reports.allSatisfy { $0["MediaSourceId"] as? String == "available" })
        #expect(reports.allSatisfy { $0["PositionTicks"] as? Int == 1_255_000_000 })
        #expect(reports.allSatisfy { $0["IsPaused"] as? Bool == true })
        #expect(reports.allSatisfy { $0["PlaySessionId"] as? String == playback.request.sessionID })
    }

    @Test("Unknown native-player selection cannot clear remembered choices, but lifecycle still reports")
    func unknownTracks() async throws {
        let client = client("fallback")
        let request = try await client.streamRequest(for: item, startingAt: 100, capabilities: .appleNative)
        func report(_ event: PlaybackReport.Event) -> PlaybackReport {
            PlaybackReport(event: event, item: item, request: request, position: .infinity, tracks: nil, selection: nil)
        }
        #expect(await client.reportPlayback(report(.started)))
        #expect(await !client.reportPlayback(report(.progress)))
        #expect(await client.reportPlayback(report(.stopped)))
        let requests = JellyfinPlaybackProtocol.log.requests.filter { $0.httpMethod == "POST" }
        #expect(requests.map { $0.url!.path } == ["/jellyfin/Sessions/Playing", "/jellyfin/Sessions/Playing/Stopped"])
        for request in requests {
            let payload = try body(request)
            #expect(payload["AudioStreamIndex"] == nil)
            #expect(payload["SubtitleStreamIndex"] == nil)
            #expect(payload["PositionTicks"] as? Int == 0)
            #expect(payload["PlayMethod"] as? String == "DirectStream")
        }
    }

    private func body(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private final class JellyfinRequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URLRequest] = []
    var requests: [URLRequest] { lock.withLock { stored } }
    func reset() { lock.withLock { stored = [] } }
    func append(_ request: URLRequest) { lock.withLock { stored.append(request) } }
}

private final class JellyfinPlaybackProtocol: URLProtocol, @unchecked Sendable {
    static let log = JellyfinRequestLog()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var recorded = request
        if recorded.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            recorded.httpBody = data
        }
        Self.log.append(recorded)
        let url = request.url!
        if url.host == "cancel.invalid" { return }
        if url.host == "offline.invalid" {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let source = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "mediaSourceId" }?.value
        let status = url.host == "unauthorized.invalid" ? 401 :
            (url.host == "missing.invalid" || source == "missing") ? 404 : 200
        let payload = url.path.hasSuffix("PlaybackInfo") ? #"{"MediaSources":[{"Id":"available","DefaultAudioStreamIndex":2,"DefaultSubtitleStreamIndex":3,"MediaStreams":[{"Type":"Subtitle","Index":0,"Language":"eng","Codec":"subrip","IsExternal":true},{"Type":"Audio","Index":2,"Language":"jpn"},{"Type":"Subtitle","Index":3,"Language":"eng","Codec":"subrip"}]}]}"# : "{}"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
