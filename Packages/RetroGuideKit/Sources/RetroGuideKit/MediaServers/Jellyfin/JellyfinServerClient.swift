import Foundation

/// ``MediaServerClient`` implementation for Jellyfin.
public struct JellyfinServerClient: MediaServerClient {
    let context: JellyfinRequestContext
    private let userID: String
    private let playback: ServerPlaybackSettings

    public init(
        serverID: String,
        baseURL: URL,
        token: String,
        userID: String,
        identity: JellyfinClientIdentity,
        playback: ServerPlaybackSettings = .local,
        http: HTTPClient = HTTPClient(),
        playbackHTTP: HTTPClient = .playback
    ) {
        context = JellyfinRequestContext(
            serverID: serverID,
            baseURL: baseURL,
            token: token,
            identity: identity,
            http: http.jellyfin,
            playbackHTTP: playbackHTTP.jellyfin
        )
        self.userID = userID
        self.playback = playback
    }

    public var serverID: String {
        context.serverID
    }

    /// Reachable only if the server answering is this one, so another
    /// Jellyfin server that took over the address isn't mistaken for it.
    public func isReachable() async -> Bool {
        guard let request = try? context.builder(timeout: JellyfinAPI.Defaults.probeTimeout).request(path: JellyfinAPI.Path.publicInfo),
              let info = try? await context.http.decode(JellyfinPublicInfo.self, for: request)
        else { return false }
        return JellyfinServerInfo.sameServer(info.id, serverID)
    }

    public func fetchLibraries() async throws -> [MediaLibrary] {
        let request = try context.builder.request(path: JellyfinAPI.Path.userViews, query: [URLQueryItem(name: "userId", value: userID)])
        let views = try await context.http.decode(JellyfinQueryResult<JellyfinItem>.self, for: request).items ?? []
        return views.map { view in
            MediaLibrary(serverID: serverID, key: view.id, title: view.name ?? view.id, kind: Self.kind(of: view.collectionType))
        }
    }

    public func fetchItems(
        in libraries: [MediaLibrary],
        progress: @escaping @Sendable (LibraryLoadProgress) -> Void
    ) async throws -> [MediaItem] {
        try await JellyfinLibraryLoader(context: context).load(libraries, progress: progress)
    }

    public func streamRequest(
        for item: MediaItem,
        startingAt position: TimeInterval,
        capabilities: PlaybackCapabilities
    ) async throws -> StreamRequest {
        let versions = MediaVersionSelector.ranked(item.versions, for: playback.quality)
        let direct = versions.filter { DirectPlayPolicy.canDirectPlay($0, with: capabilities) }
        let candidates = direct + (capabilities.playsAnyFile ? [] : versions.filter { !direct.contains($0) })
        var lastError: (any Error)?
        for version in candidates {
            guard let sourceID = version.filePath else { continue }
            try Task.checkCancellation()
            do {
                // The index can outlive a moved/deleted file. Ask for the actual
                // file's headers before choosing it, including for HLS playback.
                let original = try directPlayRequest(itemID: item.itemKey, sourceID: sourceID, position: position, version: version.index)
                var probe = URLRequest(url: original.url, timeoutInterval: JellyfinAPI.Defaults.availabilityTimeout)
                probe.httpMethod = "HEAD"
                _ = try await context.playbackHTTP.data(for: probe)
                if DirectPlayPolicy.canDirectPlay(version, with: capabilities) { return original }
                return try remuxRequest(itemID: item.itemKey, sourceID: sourceID, position: position, version: version.index)
            } catch HTTPError.unauthorized {
                throw HTTPError.unauthorized
            } catch {
                try Task.checkCancellation()
                lastError = error
            }
        }
        if lastError is URLError { throw StreamError.serverUnreachable }
        throw StreamError.noPlayableVersion
    }

    /// The original file; the player seeks to the live position itself.
    private func directPlayRequest(itemID: String, sourceID: String, position: TimeInterval, version: Int) throws -> StreamRequest {
        let sessionID = UUID().uuidString
        let url = try context.builder.url(path: JellyfinAPI.Path.stream(itemID), query: [
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "mediaSourceId", value: sourceID),
            URLQueryItem(name: "playSessionId", value: sessionID),
            URLQueryItem(name: "deviceId", value: context.identity.deviceID),
            context.apiKey,
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

    /// HLS from the server, copying the video and audio whenever Apple's
    /// player can decode them, transcoded otherwise. The playlist spans the
    /// whole item and the player seeks to the live position. (Asking the
    /// server to start there instead makes it refuse the first segment.)
    private func remuxRequest(itemID: String, sourceID: String, position: TimeInterval, version: Int) throws -> StreamRequest {
        let sessionID = UUID().uuidString
        let url = try context.builder.url(path: JellyfinAPI.Path.hlsStream(itemID), query: [
            URLQueryItem(name: "mediaSourceId", value: sourceID),
            URLQueryItem(name: "playSessionId", value: sessionID),
            URLQueryItem(name: "deviceId", value: context.identity.deviceID),
            URLQueryItem(name: "videoCodec", value: JellyfinAPI.Transcode.videoCodec),
            URLQueryItem(name: "audioCodec", value: JellyfinAPI.Transcode.audioCodec),
            URLQueryItem(name: "segmentContainer", value: JellyfinAPI.Transcode.segmentContainer),
            URLQueryItem(name: "transcodingMaxAudioChannels", value: JellyfinAPI.Transcode.maxAudioChannels),
            URLQueryItem(name: "videoBitRate", value: JellyfinAPI.Transcode.maxVideoBitrate),
            URLQueryItem(name: "allowVideoStreamCopy", value: "true"),
            URLQueryItem(name: "allowAudioStreamCopy", value: "true"),
            URLQueryItem(name: "breakOnNonKeyFrames", value: "true"),
            context.apiKey,
        ])
        return StreamRequest(
            url: url,
            startPosition: position,
            startsAtPosition: false,
            sessionID: sessionID,
            method: .directStream,
            buffer: playback.bufferProfile,
            versionIndex: version
        )
    }

    public func tracks(for item: MediaItem, version: Int?, preferences: LanguagePreferences?) async -> ItemTracks? {
        let builder = context.builder(timeout: JellyfinAPI.Defaults.trackSelectionTimeout)
        guard var request = try? builder.request(
            path: JellyfinAPI.Path.playbackInfo(item.itemKey),
            method: "POST",
            query: [URLQueryItem(name: "userId", value: userID)],
            extraHeaders: [JellyfinAPI.Header.contentType: JellyfinAPI.Header.json]
        ) else { return nil }
        request.httpBody = Data("{}".utf8)
        guard let info = try? await context.playbackHTTP.decode(JellyfinPlaybackInfo.self, for: request),
              let sources = info.mediaSources, !sources.isEmpty
        else { return nil }
        let wanted = version.flatMap { index in item.versions.first { $0.index == index }?.filePath }
        let source = sources.first { $0.id == wanted } ?? sources[0]
        return JellyfinTrackMapper.tracks(from: source, preferences: preferences) { index, format in
            try? context.builder.url(
                path: JellyfinAPI.Path.subtitle(itemID: item.itemKey, sourceID: source.id, index: index, format: format),
                query: [context.apiKey]
            )
        }
    }

    public var savesTrackChoices: Bool {
        false
    }

    /// Jellyfin keeps a viewer's track choices only from their own playback
    /// reports, and has no request that sets them for an item.
    public func saveTracks(
        for item: MediaItem,
        preferences: LanguagePreferences?,
        choose: @Sendable (_ tracks: ItemTracks, _ automatic: TrackSelection) -> TrackSelection
    ) async -> Bool {
        false
    }

    public func endStream(sessionID: String) async {
        guard let request = try? context.builder.request(
            path: JellyfinAPI.Path.activeEncodings,
            method: "DELETE",
            query: [
                URLQueryItem(name: "deviceId", value: context.identity.deviceID),
                URLQueryItem(name: "playSessionId", value: sessionID),
            ]
        ) else { return }
        _ = try? await context.playbackHTTP.data(for: request)
    }

    public func imageURL(for reference: String, size: ImageSize) -> URL? {
        guard let image = JellyfinImageReference(encoded: reference) else { return nil }
        return try? context.builder.url(path: JellyfinAPI.Path.image(image.itemID, type: image.type), query: [
            URLQueryItem(name: "tag", value: image.tag),
            URLQueryItem(name: "fillWidth", value: String(size.width)),
            URLQueryItem(name: "fillHeight", value: String(size.height)),
            URLQueryItem(name: "quality", value: JellyfinAPI.Defaults.imageQuality),
        ])
    }

    private static func kind(of collectionType: String?) -> MediaLibrary.Kind {
        switch collectionType {
        case JellyfinAPI.CollectionType.movies: .movies
        case JellyfinAPI.CollectionType.shows: .shows
        default: .unsupported
        }
    }
}
