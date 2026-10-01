import Foundation

/// Server-independent genre categories. Raw genre strings from any agent or
/// language are mapped onto these by ``GenreTaxonomy``, so built-in channels
/// work on every library.
public enum GenreCategory: String, Codable, Sendable, CaseIterable, Hashable {
    case action, adventure, animation, anime, biography, children, comedy, crime
    case documentary, drama, family, fantasy, food, gameShow, history, horror
    case martialArts, music, musical, mystery, news, reality, romance, sciFi
    case soap, sport, talk, thriller, travel, war, western

    /// Formats that make a title unscripted: documentaries, reality, game
    /// and talk shows, news. (Food and travel are topics: fiction has them too.)
    public static let unscripted: Set<GenreCategory> = [.documentary, .reality, .gameShow, .talk, .news]

    /// Categories servers' metadata applies broadly: "Mystery" on anything
    /// with a puzzle in it, TMDB's combined "Sci-Fi & Fantasy" and "Action &
    /// Adventure" TV genres, "Romance" on most comedies. They count only
    /// when ``TitleClassification`` confirms them.
    public static let looselyTagged: Set<GenreCategory> = [.mystery, .sciFi, .fantasy, .adventure, .romance]

    public var displayName: String {
        switch self {
        case .gameShow: "Game Show"
        case .martialArts: "Martial Arts"
        case .sciFi: "Science Fiction"
        case .talk: "Talk Show"
        case .children: "Kids"
        default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}

/// Whether a title is scripted (fiction, comedy, animation…) or unscripted
/// (``GenreCategory/unscripted``). Genre channels built around fiction take
/// only scripted titles.
public enum TitleFormat: String, Codable, Sendable, CaseIterable {
    case scripted
    case unscripted
}

/// Where a title's categories came from, for "Why is this here?".
public enum CategorySource: String, Sendable {
    /// RetroGuide's own title classification (``TitleClassification``).
    case classification
    /// The server's genre tags.
    case server
}
