import Foundation

/// The user's edits on top of the automatic lineup. Persisted by the app.
public struct LineupCustomization: Codable, Sendable, Hashable {
    public var hiddenChannelIDs: Set<String>
    public var orderingOverrides: [String: ScheduleOrdering]
    /// Schedule order for every automatic channel without its own override
    /// (`nil`: each channel keeps its built-in order).
    public var defaultOrdering: ScheduleOrdering?
    /// How many themed channels one show or movie may appear on.
    public var showRepeats: ShowRepeats
    public var customChannels: [ChannelDefinition]
    /// Automatic channel groups the user turned off (custom channels are never disabled).
    public var disabledSources: Set<ChannelSource>

    public init(
        hiddenChannelIDs: Set<String> = [],
        orderingOverrides: [String: ScheduleOrdering] = [:],
        defaultOrdering: ScheduleOrdering? = nil,
        showRepeats: ShowRepeats = .balanced,
        customChannels: [ChannelDefinition] = [],
        disabledSources: Set<ChannelSource> = []
    ) {
        self.hiddenChannelIDs = hiddenChannelIDs
        self.orderingOverrides = orderingOverrides
        self.defaultOrdering = defaultOrdering
        self.showRepeats = showRepeats
        self.customChannels = customChannels
        self.disabledSources = disabledSources
    }

    /// Tolerant decoding so settings saved by older versions keep working.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hiddenChannelIDs = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenChannelIDs) ?? []
        orderingOverrides = try container.decodeIfPresent([String: ScheduleOrdering].self, forKey: .orderingOverrides) ?? [:]
        defaultOrdering = try container.decodeIfPresent(ScheduleOrdering.self, forKey: .defaultOrdering)
        showRepeats = try container.decodeIfPresent(ShowRepeats.self, forKey: .showRepeats) ?? .balanced
        customChannels = try container.decodeIfPresent([ChannelDefinition].self, forKey: .customChannels) ?? []
        disabledSources = try container.decodeIfPresent(Set<ChannelSource>.self, forKey: .disabledSources) ?? []
    }

    /// Puts every channel on `ordering` at once: automatic channels through
    /// ``defaultOrdering`` and custom channels directly. Per-channel choices are
    /// cleared so the change really applies everywhere. `nil` returns every
    /// automatic channel to its built-in order.
    public mutating func setOrderingForAllChannels(_ ordering: ScheduleOrdering?) {
        defaultOrdering = ordering
        orderingOverrides.removeAll()
        guard let ordering else { return }
        for index in customChannels.indices {
            customChannels[index].ordering = ordering
        }
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
