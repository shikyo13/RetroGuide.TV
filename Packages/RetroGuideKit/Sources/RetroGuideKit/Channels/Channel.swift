import Foundation

/// A channel resolved against the current library: its definition plus the items it airs.
public struct Channel: Sendable, Identifiable, Hashable {
    public let definition: ChannelDefinition
    public let items: [MediaItem]
    public let isHidden: Bool
    public let timeline: any ChannelSchedule

    public init(definition: ChannelDefinition, items: [MediaItem], isHidden: Bool, grid: ScheduleGrid) {
        self.definition = definition
        self.items = items
        self.isHidden = isHidden
        self.timeline = Self.schedule(for: definition, items: items, grid: grid)
    }

    /// Channels with plenty of content run as a rotating lineup: shows take
    /// turns, continue where they left off and rest after finishing. Shuffle,
    /// and channels too small to keep shows rested, air everything once in a
    /// fixed order before anything repeats.
    private static func schedule(for definition: ChannelDefinition, items: [MediaItem], grid: ScheduleGrid) -> any ChannelSchedule {
        let content = items.reduce(TimeInterval.zero) { $0 + $1.duration }
        let titles = Set(items.map { $0.seriesID ?? $0.id }).count
        let hasDepth = content >= RotationTimeline.Tuning.minimumContent
            && titles >= RotationTimeline.Tuning.minimumShows
        guard definition.ordering != .shuffle, hasDepth || definition.ordering == .marathon else {
            return ChannelTimeline(channelID: definition.id, items: items, ordering: definition.ordering, grid: grid)
        }
        let plan: RotationTimeline.Plan
        switch definition.ordering {
        case .shuffle: plan = .showRotation
        case .syndication: plan = .showRotation
        case .blockShuffle: plan = .blockShuffle
        case .marathon: plan = .marathon
        }
        return RotationTimeline(channelID: definition.id, items: items, plan: plan, grid: grid)
    }

    public var id: String { definition.id }
    public var number: Int { definition.number }
    public var name: String { definition.name }
    public var callSign: String { definition.callSign }

    public var totalRuntime: TimeInterval {
        items.reduce(.zero) { $0 + $1.duration }
    }

    public static func == (lhs: Channel, rhs: Channel) -> Bool {
        lhs.definition == rhs.definition && lhs.isHidden == rhs.isHidden && lhs.items.count == rhs.items.count
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(definition)
    }
}
