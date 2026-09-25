import Foundation

/// The user's edits on top of the automatic lineup. Persisted by the app.
public struct LineupCustomization: Codable, Sendable, Hashable {
    public var hiddenChannelIDs: Set<String>
    public var orderingOverrides: [String: ScheduleOrdering]
    public var customChannels: [ChannelDefinition]
    /// Automatic channel groups the user turned off (custom channels are never disabled).
    public var disabledSources: Set<ChannelSource>

    public init(
        hiddenChannelIDs: Set<String> = [],
        orderingOverrides: [String: ScheduleOrdering] = [:],
        customChannels: [ChannelDefinition] = [],
        disabledSources: Set<ChannelSource> = []
    ) {
        self.hiddenChannelIDs = hiddenChannelIDs
        self.orderingOverrides = orderingOverrides
        self.customChannels = customChannels
        self.disabledSources = disabledSources
    }

    /// Tolerant decoding so settings saved by older versions keep working.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hiddenChannelIDs = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenChannelIDs) ?? []
        orderingOverrides = try container.decodeIfPresent([String: ScheduleOrdering].self, forKey: .orderingOverrides) ?? [:]
        customChannels = try container.decodeIfPresent([ChannelDefinition].self, forKey: .customChannels) ?? []
        disabledSources = try container.decodeIfPresent(Set<ChannelSource>.self, forKey: .disabledSources) ?? []
    }

    /// The next free number in the custom range.
    public var nextCustomChannelNumber: Int {
        let used = Set(customChannels.map(\.number))
        return ChannelNumbering.custom.first { !used.contains($0) } ?? ChannelNumbering.custom.upperBound
    }

    public static func customChannelID() -> String {
        "custom.\(UUID().uuidString.lowercased())"
    }
}
