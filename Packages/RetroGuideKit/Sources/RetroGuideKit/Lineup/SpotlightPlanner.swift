import Foundation

/// Cross-cut channels (decades, holiday, networks, collections…): the only
/// places a title appears besides its home. How often it may appear again is
/// the viewer's ``ShowRepeats`` choice.
struct SpotlightPlanner {
    enum Tuning {
        /// A spotlight needs as much content as a home channel to stay as fresh.
        static let freshnessShare = 1.0
        static let minimumTitles = 3
        static let maximumSpotlights = 24
        /// Too similar to a home channel or another spotlight to be worth a channel.
        static let duplicateSimilarity = 0.6
        /// Titles pick spotlights of these kinds first (decades feel most like TV).
        static let sourcePreference: [ChannelSource] = [.decade, .curated, .network, .collection, .library]
    }

    let extraAppearances: Int?
    let minimumHours: Double

    /// `existing` channels (homes and catch-alls) are what a spotlight must differ from.
    func plan(candidates: [ChannelDefinition], catalog: TitleCatalog, index: LibraryIndex, existing: [HomePlanner.Planned]) -> [HomePlanner.Planned] {
        var channels = candidates.map { definition in
            let rule = CompiledRule(definition.rule)
            let titles = catalog.titles.filter { title in
                title.positions.contains { rule.matches(index.items[$0], index.attributes[$0]) }
            }
            return HomePlanner.Planned(definition: definition, titles: titles)
        }
        channels = channels.filter(isViable)
        channels = removeDuplicates(channels, existing: existing)
        if let extraAppearances {
            channels = capped(channels, perTitle: extraAppearances).filter(isViable)
        }
        return Array(channels.sorted { $0.hours > $1.hours }.prefix(Tuning.maximumSpotlights))
    }

    private func isViable(_ channel: HomePlanner.Planned) -> Bool {
        channel.titles.count >= Tuning.minimumTitles && channel.hours >= minimumHours
    }

    private func rank(_ source: ChannelSource) -> Int {
        Tuning.sourcePreference.firstIndex(of: source) ?? Tuning.sourcePreference.count
    }

    /// Drops spotlights that mostly repeat an existing channel or a better spotlight.
    private func removeDuplicates(_ channels: [HomePlanner.Planned], existing: [HomePlanner.Planned]) -> [HomePlanner.Planned] {
        var kept: [Set<String>] = existing.map { Set($0.titles.map(\.id)) }
        var result: [HomePlanner.Planned] = []
        for channel in channels.sorted(by: { rank($0.definition.source) < rank($1.definition.source) }) {
            let own = Set(channel.titles.map(\.id))
            let isDuplicate = kept.contains { other in
                Double(own.intersection(other).count) / Double(own.union(other).count) >= Tuning.duplicateSimilarity
            }
            if !isDuplicate {
                kept.append(own)
                result.append(channel)
            }
        }
        return result
    }

    /// Each title keeps only its best `perTitle` spotlights: its decade first,
    /// then the most specific (smallest) channels.
    private func capped(_ channels: [HomePlanner.Planned], perTitle: Int) -> [HomePlanner.Planned] {
        var choices: [String: [Int]] = [:]
        for (index, channel) in channels.enumerated() {
            for title in channel.titles {
                choices[title.id, default: []].append(index)
            }
        }
        var allowed: [Int: Set<String>] = [:]
        for (title, options) in choices {
            let ranked = options.sorted { lhs, rhs in
                let left = rank(channels[lhs].definition.source), right = rank(channels[rhs].definition.source)
                if left != right { return left < right }
                return channels[lhs].titles.count < channels[rhs].titles.count
            }
            for index in ranked.prefix(perTitle) {
                allowed[index, default: []].insert(title)
            }
        }
        return channels.enumerated().map { index, channel in
            let keep = allowed[index] ?? []
            return HomePlanner.Planned(definition: channel.definition, titles: channel.titles.filter { keep.contains($0.id) })
        }
    }
}

/// 24/7 channels for shows with enough episodes to go a week without repeating.
enum MarathonPlanner {
    enum Tuning {
        static let freshnessDays = 7.0
        static let maximumMarathons = 12
    }

    static func plan(candidates: [ChannelDefinition], catalog: TitleCatalog) -> [HomePlanner.Planned] {
        let titles = Dictionary(uniqueKeysWithValues: catalog.titles.map { ($0.id, $0) })
        return candidates
            .compactMap { definition -> HomePlanner.Planned? in
                guard let seriesID = definition.rule.seriesIDs.first, let title = titles[seriesID],
                      title.hours >= Tuning.freshnessDays * 24
                else { return nil }
                return HomePlanner.Planned(definition: definition, titles: [title])
            }
            .sorted { $0.hours > $1.hours }
            .prefix(Tuning.maximumMarathons)
            .sorted { $0.definition.name.localizedCaseInsensitiveCompare($1.definition.name) == .orderedAscending }
    }
}
