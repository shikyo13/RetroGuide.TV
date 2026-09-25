import Foundation

/// Where a channel came from. Determines numbering range and editability.
public enum ChannelSource: String, Codable, Sendable, CaseIterable, Hashable {
    /// Genre and format channels from the bundled catalog.
    case curated
    /// Decade channels from the bundled catalog.
    case decade
    /// One channel per selected library.
    case library
    /// One channel per TV network found in the library.
    case network
    /// One channel per server collection.
    case collection
    /// A 24/7 marathon of a single long-running show.
    case series
    /// Created by the user in the channel editor.
    case custom

    public var displayName: String {
        switch self {
        case .curated: "Featured"
        case .decade: "Decades"
        case .library: "Libraries"
        case .network: "Networks"
        case .collection: "Collections"
        case .series: "Marathons"
        case .custom: "My Channels"
        }
    }
}

/// The persistent description of a channel: what it is called and what it airs.
public struct ChannelDefinition: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var number: Int
    public var name: String
    /// Short, uppercase station identifier shown in the guide (e.g. `"TOON"`).
    public var callSign: String
    public var rule: ChannelRule
    public var ordering: ScheduleOrdering
    public var source: ChannelSource

    public init(
        id: String,
        number: Int,
        name: String,
        callSign: String? = nil,
        rule: ChannelRule,
        ordering: ScheduleOrdering = .shuffle,
        source: ChannelSource
    ) {
        self.id = id
        self.number = number
        self.name = name
        self.callSign = callSign ?? CallSign.make(from: name)
        self.rule = rule
        self.ordering = ordering
        self.source = source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        number = try container.decode(Int.self, forKey: .number)
        name = try container.decode(String.self, forKey: .name)
        callSign = try container.decodeIfPresent(String.self, forKey: .callSign) ?? CallSign.make(from: name)
        rule = try container.decodeIfPresent(ChannelRule.self, forKey: .rule) ?? ChannelRule()
        ordering = try container.decodeIfPresent(ScheduleOrdering.self, forKey: .ordering) ?? .shuffle
        source = try container.decodeIfPresent(ChannelSource.self, forKey: .source) ?? .curated
    }
}
