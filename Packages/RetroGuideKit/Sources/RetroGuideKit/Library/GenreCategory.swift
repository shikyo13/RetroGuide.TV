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
        case .action: String(localized: "Action", bundle: .module, comment: "Genre.")
        case .adventure: String(localized: "Adventure", bundle: .module, comment: "Genre.")
        case .animation: String(localized: "Animation", bundle: .module, comment: "Genre.")
        case .anime: String(localized: "Anime", bundle: .module, comment: "Genre.")
        case .biography: String(localized: "Biography", bundle: .module, comment: "Genre.")
        case .children: String(localized: "Kids", bundle: .module)
        case .comedy: String(localized: "Comedy", bundle: .module, comment: "Genre.")
        case .crime: String(localized: "Crime", bundle: .module, comment: "Genre.")
        case .documentary: String(localized: "Documentary", bundle: .module, comment: "Genre.")
        case .drama: String(localized: "Drama", bundle: .module, comment: "Genre.")
        case .family: String(localized: "Family", bundle: .module)
        case .fantasy: String(localized: "Fantasy", bundle: .module, comment: "Genre.")
        case .food: String(localized: "Food", bundle: .module, comment: "Genre.")
        case .gameShow: String(localized: "Game Show", bundle: .module, comment: "Genre.")
        case .history: String(localized: "History", bundle: .module, comment: "Genre.")
        case .horror: String(localized: "Horror", bundle: .module, comment: "Genre.")
        case .martialArts: String(localized: "Martial Arts", bundle: .module, comment: "Genre.")
        case .music: String(localized: "Music", bundle: .module, comment: "Genre.")
        case .musical: String(localized: "Musical", bundle: .module, comment: "Genre.")
        case .mystery: String(localized: "Mystery", bundle: .module, comment: "Genre.")
        case .news: String(localized: "News", bundle: .module, comment: "Genre.")
        case .reality: String(localized: "Reality", bundle: .module, comment: "Genre.")
        case .romance: String(localized: "Romance", bundle: .module, comment: "Genre.")
        case .sciFi: String(localized: "Science Fiction", bundle: .module, comment: "Genre.")
        case .soap: String(localized: "Soap", bundle: .module, comment: "Genre: soap opera.")
        case .sport: String(localized: "Sport", bundle: .module, comment: "Genre.")
        case .talk: String(localized: "Talk Show", bundle: .module, comment: "Genre.")
        case .thriller: String(localized: "Thriller", bundle: .module, comment: "Genre.")
        case .travel: String(localized: "Travel", bundle: .module, comment: "Genre.")
        case .war: String(localized: "War", bundle: .module, comment: "Genre.")
        case .western: String(localized: "Western", bundle: .module, comment: "Genre.")
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
