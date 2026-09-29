import Foundation

/// A channel resolved against the current library: its definition plus the items it airs.
public struct Channel: Sendable, Identifiable, Hashable {
    public let definition: ChannelDefinition
    public let items: [MediaItem]
    public let isHidden: Bool
    public let timeline: any ChannelSchedule

    public init(definition: ChannelDefinition, items: [MediaItem], isHidden: Bool, grid: ScheduleGrid) {
        self.init(definition: definition, items: items, isHidden: isHidden, timeline: Self.schedule(for: definition, items: items, grid: grid))
    }

    init(definition: ChannelDefinition, items: [MediaItem], isHidden: Bool, timeline: any ChannelSchedule) {
        self.definition = definition
        self.items = items
        self.isHidden = isHidden
        self.timeline = timeline
    }

    /// A schedule for a channel on its own (see ``ChannelPicker``). Channels
    /// that share a simulcast limit are scheduled by a ``SimulcastCoordinator``.
    static func schedule(for definition: ChannelDefinition, items: [MediaItem], grid: ScheduleGrid) -> any ChannelSchedule {
        guard ChannelPicker.rotates(ordering: definition.ordering, items: items) else {
            return ChannelTimeline(channelID: definition.id, items: items, ordering: definition.ordering, grid: grid)
        }
        let context = ScheduleContext(channelID: definition.id, items: items, grid: grid)
        return SimulatedTimeline(channelID: definition.id, context: context, picker: ChannelPicker(ordering: definition.ordering, context: context))
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
