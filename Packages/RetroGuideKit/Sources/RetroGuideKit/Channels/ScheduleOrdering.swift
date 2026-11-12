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
    /// Everything on the channel oldest first, by release or first air date
    /// (see ``ReleaseSequence``), then from the start again.
    case releaseOrder

    public var displayName: String {
        switch self {
        case .shuffle: "Shuffle"
        case .blockShuffle: "Block Shuffle"
        case .syndication: "Show Rotation"
        case .marathon: "Marathon"
        case .releaseOrder: "Release Order"
        }
    }

    public var explanation: String {
        switch self {
        case .shuffle: "Shows in random order; each show's episodes stay in order."
        case .blockShuffle: "Shows take turns in short blocks, episodes stay in order."
        case .syndication: "One episode from each show in turn, in order."
        case .marathon: "Every episode of a show in order, then the next show."
        case .releaseOrder: "Oldest first, by the release dates on your server, then it starts over."
        }
    }

    /// Whether a schedule cycle airs every episode of every show (rather
    /// than the same number of turns per show).
    var airsEveryEpisode: Bool {
        self == .marathon || self == .releaseOrder
    }

    /// The orders offered for every channel at once. Release Order is chosen
    /// channel by channel: on every channel at once, channels couldn't step
    /// around each other and would air the same programs together.
    public static let allChannelsChoices = allCases.filter { $0 != .releaseOrder }

    /// `ordering` as an order for every channel at once: Release Order
    /// becomes Marathon, the same loop without the date order.
    public static func forAllChannels(_ ordering: ScheduleOrdering) -> ScheduleOrdering {
        ordering == .releaseOrder ? .marathon : ordering
    }
}
