import Foundation

/// How many themed channels one show or movie may appear on. Catch-all
/// channels (Everything, All Shows), 24/7 channels and custom channels don't count.
public enum ShowRepeats: String, Codable, Sendable, CaseIterable, Hashable {
    case fewer
    case balanced
    case more
    case unlimited

    /// Themed channels per title, or `nil` for no limit.
    public var channelLimit: Int? {
        switch self {
        case .fewer: 2
        case .balanced: 3
        case .more: 5
        case .unlimited: nil
        }
    }

    public var displayName: String {
        switch self {
        case .fewer: "Fewer"
        case .balanced: "Balanced"
        case .more: "More"
        case .unlimited: "No limit"
        }
    }

    public var explanation: String {
        switch self {
        case .fewer: "Each show airs on at most 2 themed channels. Most variety between channels."
        case .balanced: "Each show airs on at most 3 themed channels."
        case .more: "Each show airs on up to 5 themed channels. Good for small libraries."
        case .unlimited: "Shows air on every channel they fit."
        }
    }
}
