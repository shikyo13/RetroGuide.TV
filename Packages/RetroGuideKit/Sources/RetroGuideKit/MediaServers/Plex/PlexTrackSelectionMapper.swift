import Foundation

/// Converts Plex's streams into a ``TrackSelection``: the viewer's own choice
/// for the item when Plex has one, otherwise subtitles picked from their account
/// preferences (Plex's server doesn't apply its automatic subtitle rules; its apps do).
enum PlexTrackSelectionMapper {
    static func selection(
        from streams: [PlexStream],
        preferences: LanguagePreferences?,
        externalURL: (String) -> URL?
    ) -> TrackSelection {
        let audio = streams.first { $0.streamType == PlexAPI.StreamType.audio && $0.selected == true }
        let chosen = streams.first { $0.streamType == PlexAPI.StreamType.subtitle && $0.selected == true }
        let subtitle = chosen ?? preferences.flatMap { automaticSubtitle(in: streams, audio: audio, preferences: $0) }
        return TrackSelection(audioStreamIndex: audio?.index, subtitle: choice(for: subtitle, externalURL: externalURL))
    }

    private static func automaticSubtitle(in streams: [PlexStream], audio: PlexStream?, preferences: LanguagePreferences) -> PlexStream? {
        let subtitles = streams.filter { $0.streamType == PlexAPI.StreamType.subtitle }
        let candidates = subtitles.map { SubtitleCandidate(language: language(of: $0), isForced: $0.forced == true) }
        return SubtitleAutoSelector.choose(from: candidates, audioLanguage: audio.flatMap(language), preferences: preferences)
            .map { subtitles[$0] }
    }

    private static func language(of stream: PlexStream) -> String? {
        stream.languageTag ?? stream.languageCode
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
