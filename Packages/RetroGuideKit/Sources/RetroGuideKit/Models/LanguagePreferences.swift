import Foundation

/// When subtitles turn on automatically (for items the viewer hasn't chosen
/// tracks for), mirroring the media server account's setting.
public enum SubtitleMode: String, Codable, Sendable {
    /// Only when chosen by hand.
    case manual
    /// When the audio isn't in the preferred subtitle language; forced
    /// subtitles (signs, foreign dialogue) otherwise.
    case foreignAudio
    /// Always, in the preferred language.
    case always
}

/// The viewer's language settings from their media server account.
public struct LanguagePreferences: Codable, Equatable, Sendable {
    /// Preferred audio language (ISO 639 code), if set.
    public var audioLanguage: String?
    /// Preferred subtitle language (ISO 639 code), if set.
    public var subtitleLanguage: String?
    public var subtitleMode: SubtitleMode

    public init(audioLanguage: String?, subtitleLanguage: String?, subtitleMode: SubtitleMode) {
        self.audioLanguage = audioLanguage
        self.subtitleLanguage = subtitleLanguage
        self.subtitleMode = subtitleMode
    }
}

/// A subtitle track the viewer could get automatically.
public struct SubtitleCandidate: Equatable, Sendable {
    public let language: String?
    public let isForced: Bool

    public init(language: String?, isForced: Bool) {
        self.language = language
        self.isForced = isForced
    }
}

/// Picks subtitles automatically from ``LanguagePreferences``, the way media
/// server apps do when the viewer hasn't chosen for an item.
public enum SubtitleAutoSelector {
    /// The index in `candidates` of the subtitle to show, or `nil` for none.
    public static func choose(
        from candidates: [SubtitleCandidate],
        audioLanguage: String?,
        preferences: LanguagePreferences
    ) -> Int? {
        guard let wanted = LanguageCode.normalized(preferences.subtitleLanguage ?? preferences.audioLanguage) else {
            return nil
        }
        let inLanguage = candidates.indices.filter { LanguageCode.normalized(candidates[$0].language) == wanted }
        let full = inLanguage.first { !candidates[$0].isForced }
        let forced = inLanguage.first { candidates[$0].isForced }
        switch preferences.subtitleMode {
        case .manual:
            return nil
        case .always:
            return full ?? forced
        case .foreignAudio:
            // Unknown audio language: don't guess.
            guard let audio = LanguageCode.normalized(audioLanguage) else { return nil }
            return audio == wanted ? forced : full ?? forced
        }
    }
}
