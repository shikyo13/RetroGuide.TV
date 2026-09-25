import Foundation

/// A coarse, cross-country audience bucket derived from a content rating.
///
/// Channels filter on audiences instead of raw rating strings so that
/// "TV-Y7", "G" and "gb/U" all land in the same bucket.
public enum Audience: String, Codable, Sendable, CaseIterable, Hashable, Comparable {
    case kids
    case family
    case teen
    case mature
    case unrated

    public var displayName: String {
        switch self {
        case .kids: "Kids"
        case .family: "Family"
        case .teen: "Teen"
        case .mature: "Mature"
        case .unrated: "Unrated"
        }
    }

    public static func < (lhs: Audience, rhs: Audience) -> Bool {
        lhs.sortRank < rhs.sortRank
    }

    private var sortRank: Int {
        Self.allCases.firstIndex(of: self) ?? .zero
    }
}

// MARK: - Rating classification

public extension Audience {
    /// Maximum certificate age (inclusive) for each bucket when only an age is known.
    enum AgeThreshold {
        public static let kids = 7
        public static let family = 12
        public static let teen = 16
    }

    private static let knownRatings: [String: Audience] = [
        "tv-y": .kids, "tv-y7": .kids, "tv-y7-fv": .kids,
        "g": .family, "tv-g": .family, "pg": .family, "tv-pg": .family, "u": .family,
        "pg-13": .teen, "tv-14": .teen, "12": .teen, "12a": .teen,
        "r": .mature, "nc-17": .mature, "tv-ma": .mature, "15": .mature, "18": .mature,
        "nr": .unrated, "not rated": .unrated, "unrated": .unrated,
    ]

    /// Classifies a rating string such as `"TV-PG"` or `"gb/15"`.
    /// - Parameters:
    ///   - rating: The raw rating string reported by the server.
    ///   - age: An optional certificate age reported alongside the rating.
    static func classify(rating: String?, age: Int? = nil) -> Audience {
        if let rating {
            let normalized = rating
                .lowercased()
                .split(separator: "/")
                .last
                .map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            if let match = knownRatings[normalized] {
                return match
            }
            if let numeric = Int(normalized) {
                return classify(age: numeric)
            }
        }
        if let age {
            return classify(age: age)
        }
        return .unrated
    }

    private static func classify(age: Int) -> Audience {
        switch age {
        case ...AgeThreshold.kids: .kids
        case ...AgeThreshold.family: .family
        case ...AgeThreshold.teen: .teen
        default: .mature
        }
    }
}
