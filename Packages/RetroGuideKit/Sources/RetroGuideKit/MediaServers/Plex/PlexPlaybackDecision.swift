import Foundation

/// The server's answer to "can this client play this version?".
///
/// Plex only serves large files directly to sessions it has authorized through
/// a playback decision (smaller files are served regardless). The decision also
/// reports versions whose files are missing from disk.
enum PlexPlaybackDecision: Equatable {
    /// Playable as is; request the file at `partKey` with the same session.
    case directPlay(partKey: String)
    /// The server declined this version (for example its file was deleted).
    case unavailable
    /// No answer (network trouble); the version may still play.
    case unknown
}

struct PlexDecisionContainer: Decodable {
    let generalDecisionCode: Int?
    let metadata: [PlexDecisionMetadata]?

    enum CodingKeys: String, CodingKey {
        case generalDecisionCode
        case metadata = "Metadata"
    }

    var decision: PlexPlaybackDecision {
        guard generalDecisionCode == PlexAPI.Decision.directPlayOK,
              let partKey = metadata?.first?.media?.first?.parts?.first?.key
        else { return .unavailable }
        return .directPlay(partKey: partKey)
    }
}

struct PlexDecisionMetadata: Decodable {
    let media: [PlexMedia]?

    enum CodingKeys: String, CodingKey {
        case media = "Media"
    }
}

extension PlexServerClient {
    /// Asks the server to authorize `sessionID` to play version `mediaIndex` of `item` directly.
    func playbackDecision(for item: MediaItem, mediaIndex: Int, sessionID: String) async -> PlexPlaybackDecision {
        let builder = RequestBuilder(
            baseURL: context.baseURL,
            headers: context.builder.headers,
            timeout: PlexAPI.Defaults.playbackDecisionTimeout
        )
        let query = [
            URLQueryItem(name: "path", value: PlexAPI.Path.metadata(item.itemKey)),
            URLQueryItem(name: "mediaIndex", value: String(mediaIndex)),
            URLQueryItem(name: "partIndex", value: "0"),
            URLQueryItem(name: "protocol", value: PlexAPI.Decision.protocolHTTP),
            URLQueryItem(name: "directPlay", value: "1"),
            URLQueryItem(name: "directStream", value: "1"),
            URLQueryItem(name: "session", value: sessionID),
        ]
        let headers = [
            PlexAPI.Header.sessionIdentifier: sessionID,
            PlexAPI.Header.clientProfileName: PlexAPI.Decision.genericProfile,
            PlexAPI.Header.clientProfileExtra: PlexAPI.Decision.directPlayAnythingProfile,
        ]
        guard let request = try? builder.request(path: PlexAPI.Path.playbackDecision, query: query, extraHeaders: headers),
              let envelope = try? await context.http.decode(PlexEnvelope<PlexDecisionContainer>.self, for: request)
        else { return .unknown }
        return envelope.mediaContainer.decision
    }
}
