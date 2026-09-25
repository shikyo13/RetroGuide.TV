import Foundation

/// Server-independent genre categories. Raw genre strings from any agent or
/// language are mapped onto these by ``GenreTaxonomy``, so built-in channels
/// work on every library.
public enum GenreCategory: String, Codable, Sendable, CaseIterable, Hashable {
    case action, adventure, animation, anime, biography, children, comedy, crime
    case documentary, drama, family, fantasy, food, gameShow, history, horror
    case martialArts, music, musical, mystery, news, reality, romance, sciFi
    case soap, sport, talk, thriller, travel, war, western

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
