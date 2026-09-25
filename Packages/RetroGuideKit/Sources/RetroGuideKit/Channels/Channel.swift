import Foundation

/// A channel resolved against the current library: its definition plus the items it airs.
public struct Channel: Sendable, Identifiable, Hashable {
    public let definition: ChannelDefinition
    public let items: [MediaItem]
    public let isHidden: Bool
    public let timeline: ChannelTimeline

    public init(definition: ChannelDefinition, items: [MediaItem], isHidden: Bool, grid: ScheduleGrid) {
        self.definition = definition
        self.items = items
        self.isHidden = isHidden
        self.timeline = ChannelTimeline(
            channelID: definition.id,
            items: items,
            ordering: definition.ordering,
            grid: grid
        )
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
