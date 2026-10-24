import Foundation

/// Converts a Jellyfin media source's streams into ``ItemTracks``. The server
/// already picks the tracks to play (the viewer's remembered choice, else
/// their account's language settings), so its defaults are the selection,
/// except a subtitle in a language the viewer didn't ask for: with no
/// language set, Jellyfin shows whatever track the file flags as default
/// (often Chinese on anime releases), so the app's own rule picks instead.
///
/// Jellyfin numbers sidecar subtitle files first and the file's own streams
/// after them, so a file's audio at container index 1 is Jellyfin's index 2
/// when one sidecar exists. The player knows container indexes, so embedded
/// tracks are renumbered; sidecars keep Jellyfin's index, which their URL uses.
enum JellyfinTrackMapper {
    /// Jellyfin's `DefaultSubtitleStreamIndex` for "no subtitles".
    private static let noSubtitleIndex = -1

    /// Subtitle codecs whose sidecar file is served under another extension.
    private static let subtitleFormats = ["subrip": "srt", "webvtt": "vtt"]

    /// - Parameter externalURL: The URL serving the sidecar subtitle with this
    ///   (Jellyfin) index in this format.
    static func tracks(
        from source: JellyfinMediaSource,
        preferences: LanguagePreferences?,
        externalURL: (_ index: Int, _ format: String) -> URL?
    ) -> ItemTracks {
        let streams = source.mediaStreams ?? []
        let sidecars = streams.filter { $0.isExternal == true }.compactMap(\.index)
        func option(_ stream: JellyfinMediaStream, _ kind: TrackOption.Kind) -> TrackOption? {
            Self.option(for: stream, kind: kind, sidecars: sidecars, externalURL: externalURL)
        }
        let audio = streams.filter { $0.type == JellyfinAPI.StreamType.audio }.map { ($0, option($0, .audio)) }
        let subtitles = streams.filter { $0.type == JellyfinAPI.StreamType.subtitle }.map { ($0, option($0, .subtitle)) }
        let chosenAudio = source.defaultAudioStreamIndex.flatMap { index in audio.first { $0.0.index == index }?.1 }
        var chosenSubtitle = source.defaultSubtitleStreamIndex.flatMap { index in
            index == noSubtitleIndex ? nil : subtitles.first { $0.0.index == index }?.1
        }
        if let preferences, let wanted = LanguageCode.normalized(preferences.subtitleLanguage ?? preferences.audioLanguage),
           let server = chosenSubtitle, LanguageCode.normalized(server.language) != wanted {
            let options = subtitles.compactMap(\.1)
            let candidates = options.map { SubtitleCandidate(language: $0.language, isForced: $0.isForced) }
            chosenSubtitle = SubtitleAutoSelector.choose(from: candidates, audioLanguage: chosenAudio?.language, preferences: preferences)
                .map { options[$0] }
        }
        return ItemTracks(
            audio: audio.compactMap(\.1),
            subtitles: subtitles.compactMap(\.1),
            selection: TrackSelection(audioStreamIndex: chosenAudio?.streamIndex, subtitle: chosenSubtitle?.subtitleChoice ?? .none)
        )
    }

    private static func option(
        for stream: JellyfinMediaStream,
        kind: TrackOption.Kind,
        sidecars: [Int],
        externalURL: (_ index: Int, _ format: String) -> URL?
    ) -> TrackOption? {
        guard let index = stream.index else { return nil }
        let source: TrackOption.Source
        if stream.isExternal == true {
            let codec = (stream.codec ?? "").lowercased()
            guard let url = externalURL(index, subtitleFormats[codec] ?? codec) else { return nil }
            source = .external(url)
        } else {
            source = .embedded(streamIndex: index - sidecars.filter { $0 < index }.count)
        }
        let title = stream.displayTitle ?? stream.title ?? stream.language ?? JellyfinAPI.Defaults.unknownTrackTitle
        return TrackOption(kind: kind, source: source, language: stream.language, title: title, isForced: stream.isForced == true)
    }
}
