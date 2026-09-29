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
        var seenContent = Set<Int>()
        var resolved: [Resolved] = []
        for var definition in automatic {
            guard !customization.disabledSources.contains(definition.source) else { continue }
            if let ordering = customization.orderingOverrides[definition.id] ?? customization.defaultOrdering {
                definition.ordering = ordering
            }
            let items = schedulableItems(for: definition.rule, in: index)
            guard isSubstantial(items), seenContent.insert(contentFingerprint(items)).inserted else { continue }
            resolved.append((definition, items))
        }
        // However small the library, something should be on.
        if resolved.isEmpty, let fallback = automatic.first(where: { $0.rule.isUnconstrained && !customization.disabledSources.contains($0.source) }) {
            let items = schedulableItems(for: fallback.rule, in: index)
            if !items.isEmpty {
                resolved.append((fallback, items))
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

        return schedule(resolved, customization: customization).sorted { $0.number < $1.number }
    }

    /// Visible channels share one schedule that keeps any show from airing on
    /// more than ``LineupCustomization/simulcastLimit`` of them at once; 24/7,
    /// custom and hidden channels run on their own.
    private func schedule(_ resolved: [Resolved], customization: LineupCustomization) -> [Channel] {
        let isHidden = { (definition: ChannelDefinition) in customization.hiddenChannelIDs.contains(definition.id) }
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
                timeline: timelines[position] ?? Channel.schedule(for: definition, items: items, grid: options.grid)
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
