import Foundation

/// How many channels may air the same show at the same time. 24/7 and custom
/// channels don't count: airing one show is what 24/7 channels are for.
/// The scheduler prefers different episodes and movies when alternatives exist.
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
        case .one: "Aim to show each series on one automatic channel at a time, for more variety."
        case .two: "Aim to show each series on no more than two automatic channels at a time, using different episodes."
        case .three: "Aim to show each series on no more than three automatic channels at a time, using different episodes."
        case .unlimited: "Allow each series on any number of automatic channels at a time. Episode and movie overlap is still avoided when possible."
        }
    }
}
