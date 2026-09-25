import Foundation

/// How a channel orders its content within each schedule cycle.
public enum ScheduleOrdering: String, Codable, Sendable, CaseIterable, Hashable {
    /// Fully random order, reshuffled every cycle.
    case shuffle
    /// Shows rotate in random order, a few consecutive episodes at a time,
    /// always in broadcast order. Feels like a real network lineup.
    case blockShuffle
    /// One episode per show in turn, in broadcast order (syndicated reruns).
    case syndication
    /// Each show from its first episode to its last before the next one begins.
    case marathon

    public var displayName: String {
        switch self {
        case .shuffle: "Shuffle"
        case .blockShuffle: "Block Shuffle"
        case .syndication: "Show Rotation"
        case .marathon: "Marathon"
        }
    }

    public var explanation: String {
        switch self {
        case .shuffle: "Everything in random order."
        case .blockShuffle: "Shows take turns in short blocks, episodes stay in order."
        case .syndication: "One episode from each show in turn, in order."
        case .marathon: "Every episode of a show in order, then the next show."
        }
    }
}
