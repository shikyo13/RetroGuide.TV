import Foundation

/// ``MediaServerClient`` implementation for Plex Media Server.
public struct PlexServerClient: MediaServerClient {
    private let context: PlexRequestContext
    private let playback: ServerPlaybackSettings

    public init(
        serverID: String,
        baseURL: URL,
        token: String,
        identity: PlexClientIdentity,
        playback: ServerPlaybackSettings = .local,
        http: HTTPClient = HTTPClient()
    ) {
        context = PlexRequestContext(serverID: serverID, baseURL: baseURL, token: token, identity: identity, http: http)
        self.playback = playback
    }

    public var serverID: String {
        context.serverID
    }

    public func isReachable() async -> Bool {
        let builder = RequestBuilder(baseURL: context.baseURL, headers: context.builder.headers, timeout: PlexAPI.Defaults.probeTimeout)
        guard let request = try? builder.request(path: PlexAPI.Path.identity) else { return false }
        return (try? await context.http.data(for: request)) != nil
    }

    public func fetchLibraries() async throws -> [MediaLibrary] {
        try await context.directories(path: PlexAPI.Path.sections).map { directory in
            MediaLibrary(serverID: serverID, key: directory.key, title: directory.title, kind: Self.kind(of: directory.type))
        }
    }

    public func fetchItems(
        in libraries: [MediaLibrary],
        progress: @escaping @Sendable (LibraryLoadProgress) -> Void
    ) async throws -> [MediaItem] {
        try await PlexLibraryLoader(context: context).load(libraries, progress: progress)
    }

    public func streamRequest(
        for item: MediaItem,
        startingAt position: TimeInterval,
        capabilities: PlaybackCapabilities
    ) throws -> StreamRequest {
        let version = MediaVersionSelector.best(of: item.versions, for: playback.quality)
        if DirectPlayPolicy.canDirectPlay(version, with: capabilities), let filePath = version?.filePath {
            return try directPlayRequest(filePath: filePath, position: position)
        }
        return try directStreamRequest(for: item, mediaIndex: version?.index ?? .zero, position: position)
    }

    /// The original file; the player seeks to the live position itself.
    private func directPlayRequest(filePath: String, position: TimeInterval) throws -> StreamRequest {
        let url = try context.builder.url(path: filePath, query: [URLQueryItem(name: PlexAPI.Header.token, value: context.token)])
        return StreamRequest(
            url: url,
            startPosition: position,
            startsAtPosition: false,
            sessionID: UUID().uuidString,
            method: .directPlay,
            buffer: playback.bufferProfile
        )
    }

    /// HLS from the universal transcoder in remux mode, starting at the live position.
    private func directStreamRequest(for item: MediaItem, mediaIndex: Int, position: TimeInterval) throws -> StreamRequest {
        let sessionID = UUID().uuidString
        let offset = Int(position.rounded(.down))
        let query = context.identity.queryItems + [
            URLQueryItem(name: "path", value: PlexAPI.Path.metadata(item.itemKey)),
            URLQueryItem(name: "mediaIndex", value: String(mediaIndex)),
            URLQueryItem(name: "partIndex", value: "0"),
            URLQueryItem(name: "protocol", value: PlexAPI.Transcode.protocolHLS),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "fastSeek", value: "1"),
            URLQueryItem(name: "directPlay", value: "0"),
            URLQueryItem(name: "directStream", value: "1"),
            URLQueryItem(name: "directStreamAudio", value: "1"),
            URLQueryItem(name: "videoResolution", value: PlexAPI.Transcode.videoResolution),
            URLQueryItem(name: "maxVideoBitrate", value: String(PlexAPI.Transcode.maxVideoBitrateKbps)),
            URLQueryItem(name: "location", value: "lan"),
            URLQueryItem(name: "session", value: sessionID),
            URLQueryItem(name: "X-Plex-Client-Profile-Extra", value: PlexAPI.Transcode.profileExtra),
            URLQueryItem(name: PlexAPI.Header.token, value: context.token),
        ]
        let url = try context.builder.url(path: PlexAPI.Path.transcodeStart, query: query)
        return StreamRequest(
            url: url,
            startPosition: TimeInterval(offset),
            startsAtPosition: true,
            sessionID: sessionID,
            method: .directStream,
            buffer: playback.bufferProfile
        )
    }

    public func trackSelection(for item: MediaItem) async -> TrackSelection? {
        let builder = RequestBuilder(
            baseURL: context.baseURL,
            headers: context.builder.headers,
            timeout: PlexAPI.Defaults.trackSelectionTimeout
        )
        guard let request = try? builder.request(path: PlexAPI.Path.metadata(item.itemKey)),
              let page = try? await context.http.decode(PlexEnvelope<PlexMetadataPage>.self, for: request),
              let streams = page.mediaContainer.metadata?.first?.media?.first?.parts?.first?.streams
        else { return nil }
        return PlexTrackSelectionMapper.selection(from: streams) { key in
            try? context.builder.url(path: key, query: [URLQueryItem(name: PlexAPI.Header.token, value: context.token)])
        }
    }

    public func endStream(sessionID: String) async {
        let query = [URLQueryItem(name: "session", value: sessionID)]
        guard let request = try? context.builder.request(path: PlexAPI.Path.transcodeStop, query: query) else { return }
        _ = try? await context.http.data(for: request)
    }

    public func imageURL(for reference: String, size: ImageSize) -> URL? {
        try? context.builder.url(
            path: PlexAPI.Path.photoTranscode,
            query: [
                URLQueryItem(name: "width", value: String(size.width)),
                URLQueryItem(name: "height", value: String(size.height)),
                URLQueryItem(name: "minSize", value: "1"),
                URLQueryItem(name: "upscale", value: "1"),
                URLQueryItem(name: "url", value: reference),
                URLQueryItem(name: PlexAPI.Header.token, value: context.token),
            ]
        )
    }

    private static func kind(of type: String?) -> MediaLibrary.Kind {
        switch type {
        case PlexAPI.SectionType.movie: .movies
        case PlexAPI.SectionType.show: .shows
        default: .unsupported
        }
    }
}
