import Foundation

/// A viewer's audio and subtitle choice for a whole show, applied to every
/// episode by language (episodes number their tracks differently, so the
/// choice can't be a track number).
public struct TrackPreference: Codable, Sendable, Hashable {
    /// Audio language to play (`nil`: whatever the server picks).
    public var audioLanguage: String?
    public var subtitles: SubtitlePreference

    public init(audioLanguage: String? = nil, subtitles: SubtitlePreference = .automatic) {
        self.audioLanguage = audioLanguage
        self.subtitles = subtitles
    }

    /// The preference that picks these tracks on other episodes.
    public init(audio: TrackOption?, subtitle: TrackOption?, subtitlesOff: Bool) {
        audioLanguage = audio?.language
        if subtitlesOff {
            subtitles = .off
        } else if let subtitle {
            subtitles = .track(language: subtitle.language, isForced: subtitle.isForced, title: subtitle.title)
        } else {
            subtitles = .automatic
        }
    }

    /// The tracks to play for an item with `tracks`.
    public func selection(for tracks: ItemTracks) -> TrackSelection {
        TrackSelection(audioStreamIndex: audioStreamIndex(in: tracks), subtitle: subtitleChoice(in: tracks))
    }

    private func audioStreamIndex(in tracks: ItemTracks) -> Int? {
        guard let wanted = LanguageCode.normalized(audioLanguage),
              let match = tracks.audio.first(where: { LanguageCode.normalized($0.language) == wanted })
        else { return tracks.selection.audioStreamIndex }
        return match.streamIndex ?? tracks.selection.audioStreamIndex
    }

    private func subtitleChoice(in tracks: ItemTracks) -> SubtitleChoice {
        switch subtitles {
        case .automatic:
            return tracks.selection.subtitle
        case .off:
            return .none
        case let .track(language, isForced, title):
            let wanted = LanguageCode.normalized(language)
            let candidates = tracks.subtitles.filter { LanguageCode.normalized($0.language) == wanted && $0.isForced == isForced }
            // Several tracks in one language ("Full", "Signs & Songs"): prefer the same kind.
            let best = candidates.first { $0.title == title } ?? candidates.first
            return best?.subtitleChoice ?? .none
        }
    }
}

public enum SubtitlePreference: Codable, Sendable, Hashable {
    /// Whatever the server or the account's subtitle setting picks.
    case automatic
    case off
    /// A track in `language`, forced (signs and foreign dialogue only) or full.
    case track(language: String?, isForced: Bool, title: String)
}
