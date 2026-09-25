import Foundation

/// Resolves channel definitions against the library into the final lineup.
public struct LineupBuilder: Sendable {
    private typealias Resolved = (definition: ChannelDefinition, items: [MediaItem])

    public let curated: [ChannelDefinition]
    public let options: LineupOptions

    public init(curated: [ChannelDefinition], options: LineupOptions = LineupOptions()) {
        self.curated = curated
        self.options = options
    }

    /// Builds the lineup sorted by channel number. Hidden channels are included
    /// (flagged) so the channel manager can show them; empty or duplicate
    /// automatic channels are dropped.
    public func build(index: LibraryIndex, customization: LineupCustomization) -> [Channel] {
        let automatic = curated + DynamicChannelFactory.definitions(for: index.facets, options: options)
        var seenContent = Set<Int>()
        var resolved: [Resolved] = []

        for var definition in automatic.sorted(by: { $0.number < $1.number }) {
            guard !customization.disabledSources.contains(definition.source) else { continue }
            if let override = customization.orderingOverrides[definition.id] {
                definition.ordering = override
            }
            let items = schedulableItems(for: definition.rule, in: index)
            guard isSubstantial(items) else { continue }
            guard seenContent.insert(contentFingerprint(items)).inserted else { continue }
            resolved.append((definition, items))
        }

        resolved = capped(resolved)

        for definition in customization.customChannels {
            let items = schedulableItems(for: definition.rule, in: index)
            guard !items.isEmpty else { continue }
            resolved.append((definition, items))
        }

        var usedCallSigns = Set<String>()
        return resolved
            .sorted { $0.definition.number < $1.definition.number }
            .map { entry in
                var definition = entry.definition
                definition.callSign = CallSign.unique(definition.callSign, avoiding: &usedCallSigns)
                return makeChannel(definition, items: entry.items, customization: customization)
            }
    }

    /// Drops the least essential automatic channels beyond ``LineupOptions/maximumChannels``:
    /// collections first, then networks, marathons and libraries, smallest first.
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

    private func makeChannel(
        _ definition: ChannelDefinition,
        items: [MediaItem],
        customization: LineupCustomization
    ) -> Channel {
        Channel(
            definition: definition,
            items: items,
            isHidden: customization.hiddenChannelIDs.contains(definition.id),
            grid: options.grid
        )
    }
}
