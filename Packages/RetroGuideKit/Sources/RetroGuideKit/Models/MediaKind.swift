import Foundation

/// The kinds of playable media a channel can schedule.
public enum MediaKind: String, Codable, Sendable, CaseIterable, Hashable {
    case movie
    case episode

    public var displayName: String {
        switch self {
        case .movie: String(localized: "Movies", bundle: .module)
        case .episode: String(localized: "TV Episodes", bundle: .module)
        }
    }
}
