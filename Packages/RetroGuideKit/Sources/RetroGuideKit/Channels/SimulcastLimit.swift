import Foundation

/// How many channels may air the same show at the same time. 24/7 channels
/// don't count: airing one show is what they're for.
public enum SimulcastLimit: String, Codable, Sendable, CaseIterable, Hashable {
    case one
    case two
    case three
    case unlimited

    /// Channels allowed to air a show at once, or `nil` for no limit.
    public var channels: Int? {
        switch self {
        case .one: 1
        case .two: 2
        case .three: 3
        case .unlimited: nil
        }
    }

    public var displayName: String {
        switch self {
        case .one: "1 channel"
        case .two: "2 channels"
        case .three: "3 channels"
        case .unlimited: "No limit"
        }
    }

    public var explanation: String {
        switch self {
        case .one: "A show airs on only one channel at a time. Most variety while surfing."
        case .two: "A show airs on at most two channels at the same time."
        case .three: "A show airs on at most three channels at the same time."
        case .unlimited: "Channels schedule independently; a show may be on several at once."
        }
    }
}
