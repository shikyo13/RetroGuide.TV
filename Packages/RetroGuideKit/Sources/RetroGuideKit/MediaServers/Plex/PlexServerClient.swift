import Foundation

/// ``MediaServerClient`` implementation for Plex Media Server.
public struct PlexServerClient: MediaServerClient {
    let context: PlexRequestContext
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
    ) async throws -> StreamRequest {
        let versions = MediaVersionSelector.ranked(item.versions, for: playback.quality)
        let playable = versions.filter { DirectPlayPolicy.canDirectPlay($0, with: capabilities) }
        // The preferred copy the server authorizes, skipping ones it declines
        // (such as copies whose files were deleted).
        for version in playable {
            let sessionID = UUID().uuidString
            switch await playbackDecision(for: item, mediaIndex: version.index, sessionID: sessionID) {
            case let .directPlay(partKey):
                return try directPlayRequest(filePath: partKey, sessionID: sessionID, position: position, version: version.index)
            case .unavailable:
                continue
            case .unknown:
                // No answer from the server: try the file anyway (smaller files don't need a decision).
                guard let filePath = version.filePath else { continue }
                return try directPlayRequest(filePath: filePath, sessionID: sessionID, position: position, version: version.index)
            }
        }
        // The server declined every copy. A decision is only a server opinion, so
        // still try the preferred file rather than giving up.
        if let preferred = playable.first, let filePath = preferred.filePath {
            return try directPlayRequest(filePath: filePath, sessionID: UUID().uuidString, position: position, version: preferred.index)
        }
        if capabilities.playsAnyFile {
            throw StreamError.noPlayableVersion
        }
        return try directStreamRequest(for: item, mediaIndex: versions.first?.index ?? .zero, position: position)
    }

    /// The original file; the player seeks to the live position itself. The
    /// session identifier carries the server's permission to play it directly.
    private func directPlayRequest(filePath: String, sessionID: String, position: TimeInterval, version: Int) throws -> StreamRequest {
        let url = try context.builder.url(path: filePath, query: [
            URLQueryItem(name: PlexAPI.Header.token, value: context.token),
            URLQueryItem(name: PlexAPI.Header.sessionIdentifier, value: sessionID),
            URLQueryItem(name: PlexAPI.Header.clientIdentifier, value: context.identity.clientIdentifier),
        ])
        return StreamRequest(
            url: url,
            startPosition: position,
            startsAtPosition: false,
            sessionID: sessionID,
            method: .directPlay,
            buffer: playback.bufferProfile,
            versionIndex: version
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
            buffer: playback.bufferProfile,
            versionIndex: mediaIndex
        )
    }

    public func tracks(for item: MediaItem, version: Int?, preferences: LanguagePreferences?) async -> ItemTracks? {
        guard let parts = await parts(of: item, timeout: PlexAPI.Defaults.trackSelectionTimeout) else { return nil }
        let chosen = version.flatMap { parts.indices.contains($0) ? parts[$0] : nil } ?? parts.first ?? nil
        guard let streams = chosen?.streams else { return nil }
        return PlexTrackSelectionMapper.tracks(from: streams, preferences: preferences, externalURL: externalSubtitleURL)
    }

    public func saveTracks(
        for item: MediaItem,
        preferences: LanguagePreferences?,
        choose: @Sendable (_ tracks: ItemTracks, _ automatic: TrackSelection) -> TrackSelection
    ) async -> Bool {
        guard let parts = await parts(of: item, timeout: PlexAPI.Defaults.trackSaveTimeout)?.compactMap({ $0 }), !parts.isEmpty else { return false }
        var allSaved = true
        for part in parts {
            let saved = await save(part, preferences: preferences, choose: choose)
            allSaved = allSaved && saved
        }
        return allSaved
    }

    /// Saves the chosen tracks on one copy's file.
    private func save(
        _ part: PlexPart,
        preferences: LanguagePreferences?,
        choose: @Sendable (_ tracks: ItemTracks, _ automatic: TrackSelection) -> TrackSelection
    ) async -> Bool {
        guard let partID = part.id, let streams = part.streams else { return false }
        let tracks = PlexTrackSelectionMapper.tracks(from: streams, preferences: preferences, externalURL: externalSubtitleURL)
        let automatic = PlexTrackSelectionMapper.automaticSelection(from: streams, preferences: preferences, externalURL: externalSubtitleURL)
        let selection = choose(tracks, automatic)
        let audio = streams.first { $0.streamType == PlexAPI.StreamType.audio && $0.index == selection.audioStreamIndex }
        let subtitle = streams.first { $0.streamType == PlexAPI.StreamType.subtitle && matches($0, selection.subtitle) }
        var query: [URLQueryItem] = [URLQueryItem(name: "allParts", value: "1")]
        if let audio, audio.selected != true, let id = audio.id {
            query.append(URLQueryItem(name: "audioStreamID", value: String(id)))
        }
        let currentSubtitle = streams.first { $0.streamType == PlexAPI.StreamType.subtitle && $0.selected == true }
        if selection.subtitle == .none, currentSubtitle != nil {
            query.append(URLQueryItem(name: "subtitleStreamID", value: PlexAPI.Defaults.noSubtitleStreamID))
        } else if let subtitle, subtitle.selected != true, let id = subtitle.id {
            query.append(URLQueryItem(name: "subtitleStreamID", value: String(id)))
        }
        // Already the saved choice: nothing to write.
        guard query.count > 1 else { return true }
        let builder = RequestBuilder(baseURL: context.baseURL, headers: context.builder.headers, timeout: PlexAPI.Defaults.trackSaveTimeout)
        guard let request = try? builder.request(path: PlexAPI.Path.part(partID), method: "PUT", query: query) else { return false }
        return (try? await context.http.data(for: request)) != nil
    }

    /// The first file of every copy of the item, in the server's copy order
    /// (the order ``MediaVersion/index`` counts in; `nil` for a copy without one).
    private func parts(of item: MediaItem, timeout: TimeInterval) async -> [PlexPart?]? {
        let builder = RequestBuilder(baseURL: context.baseURL, headers: context.builder.headers, timeout: timeout)
        guard let request = try? builder.request(path: PlexAPI.Path.metadata(item.itemKey)),
              let page = try? await context.http.decode(PlexEnvelope<PlexMetadataPage>.self, for: request),
              let media = page.mediaContainer.metadata?.first?.media
        else { return nil }
        return media.map { $0.parts?.first }
    }

    private func externalSubtitleURL(_ key: String) -> URL? {
        try? context.builder.url(path: key, query: [URLQueryItem(name: PlexAPI.Header.token, value: context.token)])
    }

    private func matches(_ stream: PlexStream, _ choice: SubtitleChoice) -> Bool {
        switch choice {
        case .none: false
        case let .embedded(index): stream.index == index
        case let .external(url): stream.externalKey.flatMap(externalSubtitleURL) == url
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
