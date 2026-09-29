import Foundation

/// Resolves channel definitions against the library into the final lineup.
public struct LineupBuilder: Sendable {
    private typealias Resolved = DuplicateChannelMerger.Resolved

    public let curated: [ChannelDefinition]
    public let options: LineupOptions

    public init(curated: [ChannelDefinition], options: LineupOptions = LineupOptions()) {
        self.curated = curated
        self.options = options
    }

    /// Builds the lineup sorted by channel number: every curated, decade,
    /// library, network, collection and 24/7 channel the library can fill,
    /// numbered without gaps, then the viewer's own channels. Hidden channels
    /// are included (flagged) so the channel manager can show them; empty or
    /// duplicate automatic channels are dropped.
    ///
    /// No show airs on more than ``LineupCustomization/simulcastLimit``
    /// channels at once, except on 24/7 and custom channels.
    public func build(index: LibraryIndex, customization: LineupCustomization) -> [Channel] {
        let automatic = curated.sorted { $0.number < $1.number }
            + DynamicChannelFactory.definitions(for: index.facets, options: options)
        let enabled = automatic.filter { !customization.disabledSources.contains($0.source) }
        var seenContent = Set<Int>()
        var resolved: [Resolved] = []
        var formerIDs: [String: Set<String>] = [:]
        for definition in enabled {
            let items = schedulableItems(for: definition.rule, in: index)
            guard isSubstantial(items), seenContent.insert(contentFingerprint(items)).inserted else { continue }
            formerIDs[definition.id] = Self.formerIDs(of: definition, items: items, index: index)
            resolved.append((customized(definition, formerIDs: formerIDs[definition.id] ?? [], customization), items))
        }
        // However small the library, something should be on: the broadest
        // enabled channel with anything to air.
        if resolved.isEmpty {
            let broadestFirst = enabled.filter(\.rule.isUnconstrained) + enabled.filter { !$0.rule.isUnconstrained }
            for definition in broadestFirst {
                let items = schedulableItems(for: definition.rule, in: index)
                guard !items.isEmpty else { continue }
                resolved.append((customized(definition, formerIDs: [], customization), items))
                break
            }
        }
        let marathons = resolved.filter { $0.definition.source == .series }
        resolved = capped(DuplicateChannelMerger.merge(resolved.filter { $0.definition.source != .series }) + marathons)

        var usedCallSigns = Set<String>()
        for position in resolved.indices {
            resolved[position].definition.number = ChannelNumbering.automatic.lowerBound + position
            resolved[position].definition.callSign = CallSign.unique(resolved[position].definition.callSign, avoiding: &usedCallSigns)
        }
        for var definition in customization.customChannels {
            let items = schedulableItems(for: definition.rule, in: index)
            guard !items.isEmpty else { continue }
            definition.callSign = CallSign.unique(definition.callSign, avoiding: &usedCallSigns)
            resolved.append((definition, items))
        }

        return schedule(resolved, formerIDs: formerIDs, customization: customization).sorted { $0.number < $1.number }
    }

    /// The definition with the viewer's schedule order applied.
    private func customized(_ definition: ChannelDefinition, formerIDs: Set<String>, _ customization: LineupCustomization) -> ChannelDefinition {
        var definition = definition
        let override = customization.orderingOverrides[definition.id]
            ?? formerIDs.sorted().lazy.compactMap { customization.orderingOverrides[$0] }.first
        if let ordering = override ?? customization.defaultOrdering {
            definition.ordering = ordering
        }
        return definition
    }

    /// Ids a 24/7 channel had before shows were identified across servers
    /// (`series.<server>/<key>`), so hidden channels, schedule orders and
    /// the last watched channel carry over.
    private static func formerIDs(of definition: ChannelDefinition, items: [MediaItem], index: LibraryIndex) -> Set<String> {
        guard definition.source == .series, let showID = definition.rule.seriesIDs.first else { return [] }
        let natives = Set(items.compactMap(\.seriesID)).union(index.showAliases.filter { $0.value == showID }.keys)
        return Set(natives.map { "series.\($0)" }).subtracting([definition.id])
    }

    /// Visible channels share one schedule that keeps any show from airing on
    /// more than ``LineupCustomization/simulcastLimit`` of them at once; 24/7,
    /// custom and hidden channels run on their own.
    private func schedule(_ resolved: [Resolved], formerIDs: [String: Set<String>], customization: LineupCustomization) -> [Channel] {
        let isHidden = { (definition: ChannelDefinition) in
            customization.hiddenChannelIDs.contains(definition.id)
                || !customization.hiddenChannelIDs.isDisjoint(with: formerIDs[definition.id] ?? [])
        }
        let shared = customization.simulcastLimit.channels.map { _ in
            resolved.indices.filter { !Self.exemptSources.contains(resolved[$0].definition.source) && !isHidden(resolved[$0].definition) }
                .sorted { resolved[$0].definition.id < resolved[$1].definition.id }
        } ?? []
        var timelines: [Int: any ChannelSchedule] = [:]
        if let limit = customization.simulcastLimit.channels, !shared.isEmpty {
            let coordinator = SimulcastCoordinator(limit: limit, channels: shared.map { position in
                let definition = resolved[position].definition
                return (ScheduleContext(channelID: definition.id, items: resolved[position].items, grid: options.grid), definition.ordering)
            })
            for (member, position) in shared.enumerated() {
                timelines[position] = coordinator.timeline(for: member)
            }
        }
        return resolved.indices.map { position in
            let (definition, items) = resolved[position]
            return Channel(
                definition: definition,
                items: items,
                isHidden: isHidden(definition),
                timeline: timelines[position] ?? Channel.schedule(for: definition, items: items, grid: options.grid),
                formerIDs: formerIDs[definition.id] ?? []
            )
        }
    }

    /// 24/7 channels air one show by design, and custom channels are the viewer's call.
    private static let exemptSources: Set<ChannelSource> = [.series, .custom]

    /// Drops the least essential automatic channels beyond ``LineupOptions/maximumChannels``:
    /// collections first, then networks, 24/7 shows and libraries, smallest first.
    private func capped(_ channels: [Resolved]) -> [Resolved] {
        let excess = channels.count - options.maximumChannels
        guard excess > .zero else { return channels }
        let dropped = channels
            .filter { Self.dropPriority[$0.definition.source] != nil }
            .sorted { lhs, rhs in
                let left = Self.dropPriority[lhs.definition.source] ?? .zero
                let right = Self.dropPriority[rhs.definition.source] ?? .zero
                if left != right { return left > right }
                return runtime(lhs.items) < runtime(rhs.items)
            }
            .prefix(excess)
            .map(\.definition.id)
        let droppedIDs = Set(dropped)
        return channels.filter { !droppedIDs.contains($0.definition.id) }
    }

    /// Higher drops first; sources not listed (curated, decades, custom) are never dropped.
    private static let dropPriority: [ChannelSource: Int] = [.collection: 4, .network: 3, .series: 2, .library: 1]

    private func runtime(_ items: [MediaItem]) -> TimeInterval {
        items.reduce(.zero) { $0 + $1.duration }
    }

    /// Items a rule would air, for live previews in the channel editor.
    public func preview(rule: ChannelRule, in index: LibraryIndex) -> [MediaItem] {
        schedulableItems(for: rule, in: index)
    }

    private func schedulableItems(for rule: ChannelRule, in index: LibraryIndex) -> [MediaItem] {
        rule.matchingItems(in: index).filter { $0.duration >= ScheduleConstants.minimumProgramDuration }
    }

    private func isSubstantial(_ items: [MediaItem]) -> Bool {
        items.count >= options.minimumChannelItems
            && runtime(items) >= options.minimumChannelRuntime
    }

    private func contentFingerprint(_ items: [MediaItem]) -> Int {
        var hasher = Hasher()
        items.forEach { hasher.combine($0.id) }
        return hasher.finalize()
    }

}
