import Foundation

/// The kinds of playable media a channel can schedule.
public enum MediaKind: String, Codable, Sendable, CaseIterable, Hashable {
    case movie
    case episode

    public var displayName: String {
        switch self {
        case .movie: "Movies"
        case .episode: "TV Episodes"
        }
    }
}
