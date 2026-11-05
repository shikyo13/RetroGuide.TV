import Foundation

/// The portable part of a viewer's setup. No server addresses, tokens, media
/// files, generated timelines, PINs, entitlements or playback sessions are stored.
public struct SharedSettings: Sendable {
    public var themeID: String?
    public var showsScanlines = true
    public var scheduleGrid = ScheduleGrid.continuous
    public var commercials = CommercialBreakSettings()
    public var lineup = LineupCustomization()
    public var favoriteIDs: Set<String> = []
    public var audioRules: [String: AudioRule] = [:]
    public var subtitleRules: [String: SubtitleRule] = [:]
    public var subtitleOffsets: [String: TimeInterval] = [:]
    public var libraries: [String: Set<String>] = [:]
    public var reminders: [ProgramReminder] = []
    /// Restrictions are offered for review on each device, never auto-applied.
    public var parentalPolicy: ParentalPolicy?

    public init() {}

    public func encoded() throws -> SettingsValues {
        var result = SettingsValues()
        try result.put(themeID, "appearance/theme")
        try result.put(showsScanlines, "appearance/scanlines")
        try result.put(scheduleGrid, "schedule/grid")
        try result.put(commercials.isEnabled, "commercials/enabled")
        try result.put(commercials.count, "commercials/count")
        try Self.putMembers(commercials.libraryIDs, "commercialLibraries", into: &result)
        try Self.putMembers(favoriteIDs, "favorites", into: &result)
        try Self.putLineup(lineup, prefix: "lineup", into: &result)
        for (id, value) in audioRules { try result.put(value, SettingsValues.key("audio", id)) }
        for (id, value) in subtitleRules { try result.put(value, SettingsValues.key("subtitles", id)) }
        for (id, value) in subtitleOffsets { try result.put(value, SettingsValues.key("subtitleOffsets", id)) }
        for (id, value) in libraries { try result.put(value.sorted(), SettingsValues.key("libraries", id)) }
        for reminder in reminders { try result.put(reminder, SettingsValues.key("reminders", reminder.id)) }
        if var policy = parentalPolicy {
            let channels = policy.channelCustomization
            policy.isEnabled = false
            policy.channelCustomization = LineupCustomization()
            try result.putUnordered(policy, "parental/policy")
            try Self.putLineup(channels, prefix: "parentalLineup", into: &result)
        }
        return result
    }

    public init(values: SettingsValues) throws {
        self.init()
        themeID = try values.get(String?.self, "appearance/theme") ?? nil
        showsScanlines = try values.get(Bool.self, "appearance/scanlines") ?? showsScanlines
        scheduleGrid = try values.get(ScheduleGrid.self, "schedule/grid") ?? scheduleGrid
        commercials.isEnabled = try values.get(Bool.self, "commercials/enabled") ?? false
        commercials.count = try values.get(CommercialBreakSettings.Count.self, "commercials/count") ?? .one
        commercials.libraryIDs = Set(try values.members(Bool.self, "commercialLibraries").filter(\.value).keys)
        favoriteIDs = Set(try values.members(Bool.self, "favorites").filter(\.value).keys)
        lineup = try Self.lineup(in: values, prefix: "lineup")
        audioRules = try values.members(AudioRule.self, "audio")
        subtitleRules = try values.members(SubtitleRule.self, "subtitles")
        subtitleOffsets = try values.members(TimeInterval.self, "subtitleOffsets")
        guard subtitleOffsets.values.allSatisfy(\.isFinite) else { throw SettingsReplica.Failure.invalidRecord }
        libraries = try values.members([String].self, "libraries").mapValues(Set.init)
        reminders = try values.members(ProgramReminder.self, "reminders").values.sorted { $0.start < $1.start }
        parentalPolicy = try values.get(ParentalPolicy.self, "parental/policy")
        parentalPolicy?.isEnabled = false
        parentalPolicy?.channelCustomization = try Self.lineup(in: values, prefix: "parentalLineup")
    }

    private static func putMembers(_ ids: Set<String>, _ group: String, into values: inout SettingsValues) throws {
        for id in ids { try values.put(true, SettingsValues.key(group, id)) }
    }

    private static func putLineup(_ lineup: LineupCustomization, prefix: String, into values: inout SettingsValues) throws {
        try values.put(lineup.defaultOrdering, prefix + "/defaultOrder")
        try values.put(lineup.simulcastLimit, prefix + "/simulcast")
        try putMembers(lineup.hiddenChannelIDs, prefix + "/hidden", into: &values)
        try putMembers(Set(lineup.disabledSources.map(\.rawValue)), prefix + "/disabled", into: &values)
        for channel in lineup.customChannels { try values.putUnordered(channel, SettingsValues.key(prefix + "/custom", channel.id)) }
        for (id, order) in lineup.orderingOverrides { try values.put(order, SettingsValues.key(prefix + "/order", id)) }
        for (channel, titles) in lineup.removedTitles {
            for title in titles {
                let pair = try JSONEncoder().encode([channel, title]).base64EncodedString()
                try values.put(true, SettingsValues.key(prefix + "/removed", pair))
            }
        }
    }

    private static func lineup(in values: SettingsValues, prefix: String) throws -> LineupCustomization {
        var result = LineupCustomization()
        result.defaultOrdering = try values.get(ScheduleOrdering?.self, prefix + "/defaultOrder") ?? nil
        result.simulcastLimit = try values.get(SimulcastLimit.self, prefix + "/simulcast") ?? .two
        result.hiddenChannelIDs = Set(try values.members(Bool.self, prefix + "/hidden").filter(\.value).keys)
        result.disabledSources = Set(try values.members(Bool.self, prefix + "/disabled").filter(\.value).keys.compactMap(ChannelSource.init(rawValue:)))
        result.orderingOverrides = try values.members(ScheduleOrdering.self, prefix + "/order")
        let custom = try values.members(ChannelDefinition.self, prefix + "/custom")
        guard custom.allSatisfy({ $0.key == $0.value.id && $0.value.source == .custom }) else { throw SettingsReplica.Failure.invalidRecord }
        result.customChannels = custom.values.sorted { ($0.number, $0.id) < ($1.number, $1.id) }
        var numbers: Set<Int> = []
        for index in result.customChannels.indices {
            let number = result.customChannels[index].number
            if !ChannelNumbering.custom.contains(number) || numbers.contains(number) {
                guard let free = ChannelNumbering.custom.first(where: { !numbers.contains($0) }) else { throw SettingsReplica.Failure.capacityReached }
                result.customChannels[index].number = free
            }
            numbers.insert(result.customChannels[index].number)
        }
        for key in try values.members(Bool.self, prefix + "/removed").filter(\.value).keys {
            guard let data = Data(base64Encoded: key) else { throw SettingsReplica.Failure.invalidRecord }
            let pair = try JSONDecoder().decode([String].self, from: data)
            guard pair.count == 2 else { throw SettingsReplica.Failure.invalidRecord }
            result.removedTitles[pair[0], default: []].insert(pair[1])
        }
        return result
    }
}
