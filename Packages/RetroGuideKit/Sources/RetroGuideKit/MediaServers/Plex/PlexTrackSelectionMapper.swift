import Foundation

/// Converts Plex's per-user stream selection into a ``TrackSelection``.
enum PlexTrackSelectionMapper {
    static func selection(from streams: [PlexStream], externalURL: (String) -> URL?) -> TrackSelection {
        let audio = streams.first { $0.streamType == PlexAPI.StreamType.audio && $0.selected == true }
        let subtitle = streams.first { $0.streamType == PlexAPI.StreamType.subtitle && $0.selected == true }
        return TrackSelection(audioStreamIndex: audio?.index, subtitle: choice(for: subtitle, externalURL: externalURL))
    }

    private static func choice(for stream: PlexStream?, externalURL: (String) -> URL?) -> SubtitleChoice {
        guard let stream else { return .none }
        if let index = stream.index {
            return .embedded(streamIndex: index)
        }
        if let key = stream.key, let url = externalURL(key) {
            return .external(url)
        }
        return .none
    }
}
