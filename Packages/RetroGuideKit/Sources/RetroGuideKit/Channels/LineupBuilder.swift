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

    /// Builds the lineup sorted by channel number: catch-all, genre, decade,
    /// network, collection, library and 24/7 channels the library can fill
    /// (``ChannelCategory``), then the viewer's custom channels. Visible
    /// channels are numbered without gaps. Hidden channels are included
    /// (flagged, numbered last) so the channel manager can show them. Thin
    /// channels, near-duplicates and channels beyond the cap are left out.
    ///
    /// No show airs on more than ``LineupCustomization/simulcastLimit``
    /// channels at once (24/7 and custom channels don't count), and no episode
    /// or movie airs on two channels at once.
    public func build(index: LibraryIndex, customization: LineupCustomization) -> [Channel] {
        let automatic = curated.sorted { $0.number < $1.number }
            + DynamicChannelFactory.definitions(for: index.facets, options: options)
        let enabled = automatic.filter { !customization.disabledSources.contains($0.source) }
        let seasons = Self.regularSeasonCounts(index.items)
        // Every show is a 24/7 candidate: check seasons first, and take their
        // episodes from one grouping pass rather than a library scan each.
        let episodesByShow = Dictionary(grouping: index.items.filter { $0.series != nil && $0.duration >= ScheduleConstants.minimumProgramDuration }, by: \.showID)
        let candidates = enabled
            .filter { $0.source != .series || ($0.rule.seriesIDs.first.flatMap { seasons[$0] } ?? .zero) >= options.marathonMinimumSeasons }
            .map { definition in
                let show = definition.source == .series ? definition.rule.seriesIDs.first : nil
                let items = show.map { episodesByShow[$0] ?? [] } ?? schedulableItems(for: definition.rule, in: index)
                return (definition, Self.removing(customization.removedTitles[definition.id], from: items))
            }
        let minimumTitles = Set(index.items.map(\.showID)).count >= options.titleMinimumLibraryTitles ? options.minimumChannelTitles : 1

        // 24/7 channels skip the other rules and have their own limit.
        let marathons = candidates
            .filter { $0.0.source == .series && isSubstantial($0.1) }
            .sorted { ($0.1.count, $1.0.id) > ($1.1.count, $0.0.id) }
            .prefix(options.maximumMarathonChannels)
            .sorted { ($0.0.name.lowercased(), $0.0.id) < ($1.0.name.lowercased(), $1.0.id) }
        let decades = candidates.filter { $0.0.source == .decade }
        let others = candidates.filter { $0.0.source != .decade && $0.0.source != .series }.filter { definition, items in
            (!ChannelCategory(definition).needsSeveralTitles || DecadeChannelMerger.titleCount(items) >= minimumTitles)
                && !isFranchise(definition, items)
        }
        var resolved: [Resolved] = (others + DecadeChannelMerger.merge(decades, minimumTitles: minimumTitles))
            .filter { isSubstantial($0.1) }
            .enumerated()
            .sorted { lhs, rhs in
                (ChannelCategory(lhs.element.0), lhs.offset) < (ChannelCategory(rhs.element.0), rhs.offset)
            }
            .map(\.element)
        resolved = DuplicateChannelMerger.merge(resolved, similarity: options.nearDuplicateSimilarity)
        // However small the library, something should be on: the broadest
        // enabled channel with anything to air.
        if resolved.isEmpty, marathons.isEmpty {
            let broadestFirst = candidates.filter(\.0.rule.isUnconstrained) + candidates.filter { !$0.0.rule.isUnconstrained }
            resolved = broadestFirst.first { !$0.1.isEmpty }.map { [$0] } ?? []
        }
        resolved = LineupSelection.select(resolved, capacity: options.maximumChannels) + marathons

        var formerIDs: [String: Set<String>] = [:]
        for position in resolved.indices {
            let (definition, items) = resolved[position]
            formerIDs[definition.id] = Self.formerIDs(of: definition, items: items, index: index)
            resolved[position].definition = customized(definition, formerIDs: formerIDs[definition.id] ?? [], customization)
        }
        let isHidden = { (definition: ChannelDefinition) in
            customization.hiddenChannelIDs.contains(definition.id)
                || !customization.hiddenChannelIDs.isDisjoint(with: formerIDs[definition.id] ?? [])
        }
        // Visible channels are numbered without gaps; hidden ones follow.
        let numberingOrder = resolved.indices.filter { !isHidden(resolved[$0].definition) }
            + resolved.indices.filter { isHidden(resolved[$0].definition) }
        var usedCallSigns = Set<String>()
        for (offset, position) in numberingOrder.enumerated() {
            resolved[position].definition.number = ChannelNumbering.automatic.lowerBound + offset
        }
        for position in resolved.indices {
            resolved[position].definition.callSign = CallSign.unique(resolved[position].definition.callSign, avoiding: &usedCallSigns)
        }
        for var definition in customization.customChannels {
            let items = Self.removing(customization.removedTitles[definition.id], from: schedulableItems(for: definition.rule, in: index))
            guard !items.isEmpty else { continue }
            definition.callSign = CallSign.unique(definition.callSign, avoiding: &usedCallSigns)
            resolved.append((definition, items))
        }

        return schedule(resolved, isHidden: isHidden, formerIDs: formerIDs, customization: customization).sorted { $0.number < $1.number }
    }

    /// `items` less the shows and movies removed from the channel by hand.
    private static func removing(_ removed: Set<String>?, from items: [MediaItem]) -> [MediaItem] {
        guard let removed, !removed.isEmpty else { return items }
        return items.filter { !removed.contains($0.showID) }
    }

    /// A collection of a few movies only: one film franchise, not a channel.
    private func isFranchise(_ definition: ChannelDefinition, _ items: [MediaItem]) -> Bool {
        definition.source == .collection
            && items.allSatisfy { $0.kind == .movie }
            && DecadeChannelMerger.titleCount(items) < options.movieCollectionMinimumTitles
    }

    /// Regular (non-special) seasons of every show, by show id.
    private static func regularSeasonCounts(_ items: [MediaItem]) -> [String: Int] {
        var seasons: [String: Set<Int>] = [:]
        for item in items {
            guard let series = item.series, !series.isSpecial, let season = series.seasonNumber else { continue }
            seasons[item.showID, default: []].insert(season)
        }
        return seasons.mapValues(\.count)
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

    /// Ids a channel had before, so hidden channels, schedule orders and the
    /// last watched channel carry over: a merged decade channel's members,
    /// and a 24/7 channel's ids from before shows were identified across
    /// servers (`series.<server>/<key>`).
    private static func formerIDs(of definition: ChannelDefinition, items: [MediaItem], index: LibraryIndex) -> Set<String> {
        let members = DecadeChannelMerger.memberIDs(of: definition)
        guard members.isEmpty else { return members }
        guard definition.source == .series, let showID = definition.rule.seriesIDs.first else { return [] }
        let natives = Set(items.compactMap(\.seriesID)).union(index.showAliases.filter { $0.value == showID }.keys)
        return Set(natives.map { "series.\($0)" }).subtracting([definition.id])
    }

    /// Visible channels share one schedule: no show on more than
    /// ``LineupCustomization/simulcastLimit`` of them at once (24/7 and custom
    /// channels don't count), and never the same episode or movie on two at
    /// once, 24/7 channels included. 24/7 channels repeat a fixed cycle that
    /// the others work around; hidden channels run on their own.
    private func schedule(
        _ resolved: [Resolved],
        isHidden: (ChannelDefinition) -> Bool,
        formerIDs: [String: Set<String>],
        customization: LineupCustomization
    ) -> [Channel] {
        var timelines: [Int: any ChannelSchedule] = [:]
        var fixed: [(item: MediaItem, slot: RepeatingSlot)] = []
        var shared: [Int] = []
        for position in resolved.indices where !isHidden(resolved[position].definition) {
            let (definition, items) = resolved[position]
            if Self.exemptSources.contains(definition.source), Channel.airsOneShow(items) {
                let timeline = ChannelTimeline(channelID: definition.id, items: items, ordering: definition.ordering, grid: options.grid)
                timelines[position] = timeline
                fixed += timeline.repeatingSlots()
            } else {
                shared.append(position)
            }
        }
        shared.sort { resolved[$0].definition.id < resolved[$1].definition.id }
        if !shared.isEmpty {
            let coordinator = SimulcastCoordinator(
                limit: customization.simulcastLimit.channels ?? .max,
                channels: shared.map { position in
                    let definition = resolved[position].definition
                    return (ScheduleContext(channelID: definition.id, items: resolved[position].items, grid: options.grid), definition.ordering)
                },
                uncounted: Set(shared.indices.filter { Self.exemptSources.contains(resolved[shared[$0]].definition.source) }),
                fixed: fixed
            )
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

    /// Channels that don't count toward the simulcast limit: 24/7 channels
    /// air one show by design, and custom channels are the viewer's call.
    private static let exemptSources: Set<ChannelSource> = [.series, .custom]

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


}
