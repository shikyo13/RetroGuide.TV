import Foundation

/// Resolves channel definitions against the library into the final lineup.
public struct LineupBuilder: Sendable {
    public let themes: [ChannelTheme]
    public let options: LineupOptions

    public init(themes: [ChannelTheme], options: LineupOptions = LineupOptions()) {
        self.themes = themes
        self.options = options
    }

    /// Plain definitions (tests, older callers): roles come from the bundled
    /// catalog when the id is known, otherwise an unconstrained rule is a
    /// catch-all, a decade channel a spotlight and anything else a home.
    public init(curated: [ChannelDefinition], options: LineupOptions = LineupOptions()) {
        let known = Dictionary(((try? ChannelCatalog.themes()) ?? []).map { ($0.definition.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.init(themes: curated.map { definition in
            if let theme = known[definition.id] {
                return ChannelTheme(definition: definition, role: theme.role, family: theme.family)
            }
            let rule = definition.rule
            let isCatchAll = rule.categories.isEmpty && rule.genres.isEmpty && rule.networks.isEmpty && rule.collections.isEmpty
                && rule.seriesIDs.isEmpty && rule.keywords.isEmpty && rule.audiences.isEmpty && rule.decades.isEmpty && rule.libraryIDs.isEmpty
            let role: ChannelTheme.Role = isCatchAll ? .catchAll : (definition.source == .decade ? .spotlight : .home)
            return ChannelTheme(definition: definition, role: role, family: nil)
        }, options: options)
    }

    /// Builds the lineup sorted by channel number: catch-alls, one home channel
    /// per title, spotlights (the only repeats, as many as ``ShowRepeats``
    /// allows) and 24/7 channels, then the viewer's own channels. Hidden
    /// channels are included (flagged) so the channel manager can show them.
    public func build(index: LibraryIndex, customization: LineupCustomization) -> [Channel] {
        let catalog = TitleCatalog(index: index)
        let enabled = themes.filter { !customization.disabledSources.contains($0.definition.source) }
        let dynamic = DynamicChannelFactory.definitions(for: index.facets, options: options)
            .filter { !customization.disabledSources.contains($0.source) }

        let catchAlls = enabled.filter { $0.role == .catchAll }.compactMap { theme -> HomePlanner.Planned? in
            let rule = CompiledRule(theme.definition.rule)
            let titles = catalog.titles.filter { rule.matches(index.items[$0.positions[0]], index.attributes[$0.positions[0]]) }
            return titles.isEmpty ? nil : HomePlanner.Planned(definition: theme.definition, titles: titles)
        }
        let homes = HomePlanner(themes: enabled).plan(catalog, index: index)
        // A catch-all airing exactly what one home channel airs adds nothing.
        let homeContents = Set(homes.map { Set($0.titles.map(\.id)) })
        let distinctCatchAlls = catchAlls.filter { !homeContents.contains(Set($0.titles.map(\.id))) }
        let sizing = HomePlanner.Sizing(totalHours: catalog.titles.reduce(0) { $0 + $1.hours }, freshnessDays: HomePlanner.Tuning.movieFreshnessDays)
        let spotlightHours = sizing.merge * SpotlightPlanner.Tuning.freshnessShare
        // Library structure is only a hint: how someone splits their server into
        // libraries says little about what makes a good channel.
        let spotlightCandidates = enabled.filter { $0.role == .spotlight }.map(\.definition)
            + dynamic.filter { $0.source != .series && $0.source != .library }
        let spotlights = SpotlightPlanner(extraAppearances: customization.showRepeats.channelLimit.map { max($0 - 1, 0) }, minimumHours: spotlightHours)
            .plan(candidates: spotlightCandidates, catalog: catalog, index: index, existing: homes + distinctCatchAlls)
        let marathons = MarathonPlanner.plan(candidates: dynamic.filter { $0.source == .series }, catalog: catalog)

        let sectioned: [(HomePlanner.Planned, ChannelNumberer.Section)] =
            distinctCatchAlls.sorted { $0.definition.number < $1.definition.number }.map { ($0, .catchAll) }
            + homes.filter(\.isShowChannel).map { ($0, .showHomes) }
            + homes.filter { !$0.isShowChannel }.map { ($0, .movieHomes) }
            + spotlights.map { ($0, .spotlights) }
            + marathons.map { ($0, .marathons) }
        let numbered = ChannelNumberer.number(sectioned.map { ($0.0.definition, $0.1) }, saved: customization.channelNumbers)

        var usedCallSigns = Set<String>()
        var channels: [Channel] = zip(numbered, sectioned).map { definition, entry in
            var definition = definition
            if let ordering = customization.orderingOverrides[definition.id] ?? customization.defaultOrdering {
                definition.ordering = ordering
            }
            definition.callSign = CallSign.unique(definition.callSign, avoiding: &usedCallSigns)
            let items = entry.0.titles.flatMap { $0.positions.map { index.items[$0] } }
            return makeChannel(definition, items: items, customization: customization)
        }
        for var definition in customization.customChannels {
            let items = schedulableItems(for: definition.rule, in: index)
            guard !items.isEmpty else { continue }
            definition.callSign = CallSign.unique(definition.callSign, avoiding: &usedCallSigns)
            channels.append(makeChannel(definition, items: items, customization: customization))
        }
        return channels.sorted { $0.number < $1.number }
    }

    /// Items a rule would air, for live previews in the channel editor.
    public func preview(rule: ChannelRule, in index: LibraryIndex) -> [MediaItem] {
        schedulableItems(for: rule, in: index)
    }

    private func schedulableItems(for rule: ChannelRule, in index: LibraryIndex) -> [MediaItem] {
        rule.matchingItems(in: index).filter { $0.duration >= ScheduleConstants.minimumProgramDuration }
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
