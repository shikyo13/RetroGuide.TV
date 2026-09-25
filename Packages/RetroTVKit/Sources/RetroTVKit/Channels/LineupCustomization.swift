import Foundation

/// The user's edits on top of the automatic lineup. Persisted by the app.
public struct LineupCustomization: Codable, Sendable, Hashable {
    public var hiddenChannelIDs: Set<String>
    public var orderingOverrides: [String: ScheduleOrdering]
    public var customChannels: [ChannelDefinition]

    public init(
        hiddenChannelIDs: Set<String> = [],
        orderingOverrides: [String: ScheduleOrdering] = [:],
        customChannels: [ChannelDefinition] = []
    ) {
        self.hiddenChannelIDs = hiddenChannelIDs
        self.orderingOverrides = orderingOverrides
        self.customChannels = customChannels
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
