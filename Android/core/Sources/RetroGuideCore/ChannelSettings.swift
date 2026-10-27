import Foundation
import RetroGuideKit

/// What Settings › Channels shows.
struct LineupSettings: Encodable, Sendable {
    struct Group: Encodable, Sendable {
        let id: String
        let name: String
        let isEnabled: Bool
        let channelCount: Int
    }

    struct Described: Encodable, Sendable {
        let id: String
        let title: String
        let detail: String
    }

    let channelCount: Int
    let hiddenCount: Int
    let favoriteCount: Int
    let removedTitleCount: Int
    let simulcastLimit: String
    let simulcastLimits: [Described]
    /// `nil`: each channel's own order.
    let defaultOrdering: String?
    let orderings: [Described]
    let scheduleGrid: String
    let scheduleGrids: [OptionsInfo.Choice]
    /// Groups of automatic channels that can be switched off.
    let groups: [Group]
    let canCreateCustomChannel: Bool
    let canChangeScheduling: Bool
    let canAddServer: Bool
}

/// A channel in Settings › Manage channels.
struct ChannelSummary: Encodable, Sendable {
    let id: String
    let number: Int
    let name: String
    let isHidden: Bool
    let isFavorite: Bool
    let source: String
    let sourceName: String
    /// "412 programs · 210 hours".
    let size: String
}

struct ChannelDetail: Encodable, Sendable {
    let channel: ChannelSummary
    let featuring: [String]
    let ordering: String
    let removedTitles: [RemovedTitle]
    let draft: ChannelDraft?
}

struct RemovedTitle: Encodable, Sendable {
    let showID: String
    let name: String
}

struct RemovedGroup: Encodable, Sendable {
    let channelID: String
    let channelName: String
    let titles: [RemovedTitle]
}

/// A custom channel as the editor sees it.
struct ChannelDraft: Codable, Sendable {
    /// `nil` for a new channel.
    let id: String?
    let name: String
    let ordering: String
    let kinds: [String]
    let categories: [String]
    let seriesIDs: [String]
    let networks: [String]
    let collections: [String]
    let decades: [Int]
    let audiences: [String]
    let libraryIDs: [String]
}

struct FacetOptionInfo: Encodable, Sendable {
    let id: String
    let title: String
    let detail: String?
}

/// Everything a custom channel can be built from.
struct ChannelFacets: Encodable, Sendable {
    let kinds: [FacetOptionInfo]
    let categories: [FacetOptionInfo]
    let series: [FacetOptionInfo]
    let networks: [FacetOptionInfo]
    let collections: [FacetOptionInfo]
    let decades: [FacetOptionInfo]
    let audiences: [FacetOptionInfo]
    let libraries: [FacetOptionInfo]
}

struct ChannelPreview: Encodable, Sendable {
    let programCount: Int
    let summary: String
    let shows: [String]
}

struct SourceParams: Decodable, Sendable {
    let source: String
    let isEnabled: Bool
}

struct ValueParams: Decodable, Sendable {
    /// `nil` clears the setting (each channel's own order).
    let value: String?
}

extension CoreState {
    private enum Layout {
        static let featuredShowCount = 8
        static let previewShowCount = 6
    }

    /// Groups the viewer may switch off. Custom channels always stay.
    private static let toggleableSources: [ChannelSource] = [.curated, .decade, .library, .network, .collection, .series]

    func lineupSettings() -> LineupSettings {
        let access = ProAccess(isPro: isPro)
        return LineupSettings(
            channelCount: channels.count,
            hiddenCount: channels.filter(\.isHidden).count,
            favoriteCount: channels.filter(viewing.isFavorite).count,
            removedTitleCount: customization.removedTitles.values.reduce(.zero) { $0 + $1.count },
            simulcastLimit: customization.simulcastLimit.rawValue,
            simulcastLimits: SimulcastLimit.allCases.map { LineupSettings.Described(id: $0.rawValue, title: $0.displayName, detail: $0.explanation) },
            defaultOrdering: customization.defaultOrdering?.rawValue,
            orderings: ScheduleOrdering.allCases.map { LineupSettings.Described(id: $0.rawValue, title: $0.displayName, detail: $0.explanation) },
            scheduleGrid: String(scheduleGrid.rawValue),
            scheduleGrids: ScheduleGrid.allCases.map { OptionsInfo.Choice(id: String($0.rawValue), title: $0.displayName) },
            groups: Self.toggleableSources.map { source in
                LineupSettings.Group(
                    id: source.rawValue,
                    name: source.displayName,
                    isEnabled: !customization.disabledSources.contains(source),
                    channelCount: channels.filter { $0.definition.source == source }.count
                )
            },
            canCreateCustomChannel: access.canCreateCustomChannel(existingCount: customization.customChannels.count),
            canChangeScheduling: access.canChangeScheduling,
            canAddServer: access.canAddServer(connectedCount: accounts.count)
        )
    }

    /// Every channel, hidden ones too, grouped by source in lineup order.
    func manageChannels() -> [ChannelSummary] {
        ChannelSource.allCases.flatMap { source in
            channels.filter { $0.definition.source == source }.map(summary)
        }
    }

    private func summary(_ channel: Channel) -> ChannelSummary {
        ChannelSummary(
            id: channel.id,
            number: channel.number,
            name: channel.name,
            isHidden: channel.isHidden,
            isFavorite: viewing.isFavorite(channel),
            source: channel.definition.source.rawValue,
            sourceName: channel.definition.source.displayName,
            size: "\(channel.items.count) programs · \(Self.hours(channel.totalRuntime))"
        )
    }

    func channelDetail(_ params: ChannelParams) throws -> ChannelDetail {
        guard let channel = channel(withID: params.channelID) else { throw CoreError.unknownChannel }
        return ChannelDetail(
            channel: summary(channel),
            featuring: Array(Set(channel.items.map(\.headline))).sorted().prefix(Layout.featuredShowCount).map { $0 },
            ordering: channel.definition.ordering.rawValue,
            removedTitles: removedTitles(on: channel.id),
            draft: channel.definition.source == .custom ? draft(of: channel.definition) : nil
        )
    }

    func removedTitleGroups() -> [RemovedGroup] {
        let numbers = Dictionary(channels.map { ($0.id, $0.number) }, uniquingKeysWith: { first, _ in first })
        return customization.removedTitles.keys
            .sorted { lhs, rhs in
                let left = numbers[lhs] ?? .max, right = numbers[rhs] ?? .max
                return left != right ? left < right : lhs < rhs
            }
            .map { id in
                RemovedGroup(
                    channelID: id,
                    channelName: channels.first { $0.id == id }.map { "\($0.number) · \($0.name)" } ?? "A channel no longer in the lineup",
                    titles: removedTitles(on: id)
                )
            }
    }

    private func removedTitles(on channelID: String) -> [RemovedTitle] {
        (customization.removedTitles[channelID] ?? [])
            .map { showID in RemovedTitle(showID: showID, name: index?.items.first { $0.showID == showID }?.headline ?? "A show no longer in your library") }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Lineup-wide settings

    func setSource(_ params: SourceParams) throws -> [ChannelInfo] {
        guard let source = ChannelSource(rawValue: params.source) else { throw CoreError.unknownChannel }
        return updateCustomization { customization in
            if params.isEnabled {
                customization.disabledSources.remove(source)
            } else {
                customization.disabledSources.insert(source)
            }
        }
    }

    func setSimulcastLimit(_ params: ValueParams) -> [ChannelInfo] {
        guard let limit = params.value.flatMap(SimulcastLimit.init(rawValue:)) else { return channelList() }
        return updateCustomization { $0.simulcastLimit = limit }
    }

    /// One schedule order for every channel (`nil`: each channel's own).
    func setOrderingForAllChannels(_ params: ValueParams) -> [ChannelInfo] {
        updateCustomization { $0.setOrderingForAllChannels(params.value.flatMap(ScheduleOrdering.init(rawValue:))) }
    }

    func setScheduleGrid(_ params: ValueParams) -> [ChannelInfo] {
        guard let grid = params.value.flatMap(Int.init).flatMap(ScheduleGrid.init(rawValue:)) else { return channelList() }
        scheduleGrid = grid
        store?.save(CorePreferences(scheduleGrid: grid), file: CoreStore.File.preferences)
        rebuildChannels()
        return channelList()
    }

    // MARK: - Custom channels

    func channelFacets() -> ChannelFacets {
        let facets = index?.facets
        func options(_ values: [FacetValue]?) -> [FacetOptionInfo] {
            (values ?? []).map { FacetOptionInfo(id: $0.id, title: $0.name, detail: "\($0.itemCount) · \(Self.hours($0.runtime))") }
        }
        return ChannelFacets(
            kinds: MediaKind.allCases.map { FacetOptionInfo(id: $0.rawValue, title: $0.displayName, detail: nil) },
            categories: options(facets?.categories),
            series: options(facets?.series),
            networks: options(facets?.networks),
            collections: options(facets?.collections),
            decades: options(facets?.decades),
            audiences: Audience.allCases.map { FacetOptionInfo(id: $0.rawValue, title: $0.displayName, detail: nil) },
            libraries: options(facets?.libraries)
        )
    }

    func previewChannel(_ draft: ChannelDraft) -> ChannelPreview {
        guard let index else { return ChannelPreview(programCount: .zero, summary: "Nothing matches yet", shows: []) }
        let items = LineupBuilder(curated: []).preview(rule: rule(from: draft, base: ChannelRule()), in: index)
        let runtime = items.reduce(.zero) { $0 + $1.duration }
        return ChannelPreview(
            programCount: items.count,
            summary: items.isEmpty ? "Nothing matches yet" : "\(items.count) programs · \(Self.hours(runtime))",
            shows: Array(Set(items.map(\.headline))).sorted().prefix(Layout.previewShowCount).map { $0 }
        )
    }

    func saveCustomChannel(_ draft: ChannelDraft) -> [ChannelInfo] {
        let existing = draft.id.flatMap { id in customization.customChannels.first { $0.id == id } }
        var definition = existing ?? ChannelDefinition(
            id: LineupCustomization.customChannelID(),
            number: customization.nextCustomChannelNumber,
            name: "",
            rule: ChannelRule(),
            ordering: .blockShuffle,
            source: .custom
        )
        definition.name = draft.name.trimmingCharacters(in: .whitespaces)
        definition.callSign = CallSign.make(from: definition.name)
        definition.rule = rule(from: draft, base: definition.rule)
        definition.ordering = ScheduleOrdering(rawValue: draft.ordering) ?? definition.ordering
        return updateCustomization { customization in
            if let index = customization.customChannels.firstIndex(where: { $0.id == definition.id }) {
                customization.customChannels[index] = definition
            } else {
                customization.customChannels.append(definition)
            }
        }
    }

    func deleteCustomChannel(_ params: ChannelParams) -> [ChannelInfo] {
        updateCustomization { customization in
            customization.customChannels.removeAll { $0.id == params.channelID }
            customization.hiddenChannelIDs.remove(params.channelID)
        }
    }

    private func draft(of definition: ChannelDefinition) -> ChannelDraft {
        let rule = definition.rule
        return ChannelDraft(
            id: definition.id,
            name: definition.name,
            ordering: definition.ordering.rawValue,
            kinds: rule.kinds.map(\.rawValue).sorted(),
            categories: rule.categories.map(\.rawValue).sorted(),
            seriesIDs: rule.seriesIDs.sorted(),
            networks: rule.networks.sorted(),
            collections: rule.collections.sorted(),
            decades: rule.decades.sorted(),
            audiences: rule.audiences.map(\.rawValue).sorted(),
            libraryIDs: rule.libraryIDs.sorted()
        )
    }

    /// `base` with the editor's filters (other rule fields are kept).
    private func rule(from draft: ChannelDraft, base: ChannelRule) -> ChannelRule {
        var rule = base
        rule.kinds = Set(draft.kinds.compactMap(MediaKind.init(rawValue:)))
        rule.categories = Set(draft.categories.compactMap(GenreCategory.init(rawValue:)))
        rule.seriesIDs = Set(draft.seriesIDs)
        rule.networks = Set(draft.networks)
        rule.collections = Set(draft.collections)
        rule.decades = Set(draft.decades)
        rule.audiences = Set(draft.audiences.compactMap(Audience.init(rawValue:)))
        rule.libraryIDs = Set(draft.libraryIDs)
        return rule
    }

    /// "1 hour" or "210 hours".
    private static func hours(_ interval: TimeInterval) -> String {
        let hours = Int(interval / ScheduleConstants.secondsPerHour)
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }
}

/// Settings the core keeps besides the lineup's.
struct CorePreferences: Codable, Sendable {
    var scheduleGrid: ScheduleGrid
}
