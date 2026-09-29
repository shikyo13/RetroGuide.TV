import Foundation

/// Trims the automatic lineup for variety: merges near-duplicate channels,
/// limits how many themed channels one title appears on (``ShowRepeats``),
/// and makes sure every title keeps at least one themed channel.
///
/// Catch-all channels (covering almost the whole library) and 24/7 series
/// channels are left untouched; they're what they are by design.
struct LineupVariety {
    typealias Resolved = (definition: ChannelDefinition, items: [MediaItem])

    enum Tuning {
        /// A channel whose titles cover this share of the library is a catch-all.
        static let catchAllShare = 0.9
        /// Two channels sharing this much of their combined titles are duplicates.
        static let duplicateSimilarity = 0.6
        /// Themed channels with fewer distinct shows or movies are dropped…
        static let minimumTitles = 3
        /// …once the library is big enough that thin channels are just repeats.
        static let minimumTitlesLibrarySize = 40
        /// Assignment is repeated after dropping thin channels, at most this often.
        static let maximumPasses = 4
    }

    let limit: Int?
    let isSubstantial: ([MediaItem]) -> Bool
    let taxonomy: GenreTaxonomy

    /// Distinct titles in the library, split into shows and movies.
    struct LibraryTitles {
        let shows: Int
        let movies: Int

        init(_ items: [MediaItem]) {
            shows = Set(items.compactMap(\.seriesID)).count
            movies = items.filter { $0.seriesID == nil }.count
        }
    }

    func apply(_ channels: [Resolved], library: LibraryTitles) -> [Resolved] {
        let minimumTitles = library.shows + library.movies >= Tuning.minimumTitlesLibrarySize ? Tuning.minimumTitles : 1
        let isViable: (Resolved) -> Bool = { titles(of: $0.items).count >= minimumTitles && isSubstantial($0.items) }
        let fixed = channels.filter { isFixed($0, library: library) }
        var themed = removeDuplicates(channels.filter { !isFixed($0, library: library) })
        var assigned = themed
        for _ in 0..<Tuning.maximumPasses {
            assigned = assign(themed)
            let survivors = assigned.filter(isViable)
            if survivors.count == assigned.count { break }
            let survivingIDs = Set(survivors.map(\.definition.id))
            themed = themed.filter { survivingIDs.contains($0.definition.id) }
        }
        assigned = restoringOrphans(assigned.filter(isViable), candidates: themed)
        let keptIDs = Set((fixed + assigned).map(\.definition.id))
        let replacement = Dictionary(uniqueKeysWithValues: assigned.map { ($0.definition.id, $0) })
        return channels.compactMap { channel in
            guard keptIDs.contains(channel.definition.id) else { return nil }
            return replacement[channel.definition.id] ?? channel
        }
    }

    // MARK: - Classification

    /// 24/7 channels, and channels that air (nearly) every show or every movie.
    private func isFixed(_ channel: Resolved, library: LibraryTitles) -> Bool {
        guard channel.definition.source != .series else { return true }
        let own = LibraryTitles(channel.items)
        let coversShows = own.shows > 0 && Double(own.shows) >= Tuning.catchAllShare * Double(library.shows)
        let coversMovies = own.movies > 0 && Double(own.movies) >= Tuning.catchAllShare * Double(library.movies)
        return (own.movies == 0 && coversShows) || (own.shows == 0 && coversMovies) || (coversShows && coversMovies)
    }

    // MARK: - Duplicates

    /// Keeps the most meaningful channel of each group of near-identical ones.
    /// A dropped duplicate's extra titles move into the channel that's kept, so
    /// nothing loses its home.
    private func removeDuplicates(_ channels: [Resolved]) -> [Resolved] {
        var kept: [(channel: Resolved, titles: Set<String>)] = []
        for channel in channels.sorted(by: isMoreMeaningful) {
            let own = titles(of: channel.items)
            let match = kept.firstIndex { other in
                let shared = Double(own.intersection(other.titles).count)
                return shared / Double(own.union(other.titles).count) >= Tuning.duplicateSimilarity
            }
            guard let match else {
                kept.append((channel, own))
                continue
            }
            let extra = channel.items.filter { !kept[match].titles.contains(Self.title(of: $0)) }
            kept[match].channel.items += extra
            kept[match].titles.formUnion(own)
        }
        return kept.map(\.channel)
    }

    private func isMoreMeaningful(_ lhs: Resolved, _ rhs: Resolved) -> Bool {
        let left = Self.sourceRank[lhs.definition.source] ?? .max
        let right = Self.sourceRank[rhs.definition.source] ?? .max
        if left != right { return left < right }
        return lhs.definition.number < rhs.definition.number
    }

    /// Kinds of channel each title gets one of (when it fits any) before the rest.
    private static let guaranteedSources: Set<ChannelSource> = [.curated, .decade]

    /// Lower is preferred when a title has to choose between channels.
    private static let sourceRank: [ChannelSource: Int] = [.curated: 0, .decade: 1, .library: 2, .network: 3, .collection: 4]

    // MARK: - Assignment

    /// Gives every title its best `limit` channels, specific and on-genre first.
    private func assign(_ channels: [Resolved]) -> [Resolved] {
        guard let limit else { return channels }
        var candidates: [String: [Int]] = [:]
        var representative: [String: MediaItem] = [:]
        for (index, channel) in channels.enumerated() {
            for (title, item) in titleItems(of: channel.items) {
                candidates[title, default: []].append(index)
                representative[title] = representative[title] ?? item
            }
        }
        let sizes = channels.map { titles(of: $0.items).count }
        var allowed: [Int: Set<String>] = [:]
        for (title, channelIndices) in candidates {
            guard let item = representative[title] else { continue }
            let primary = taxonomy.categories(for: Array(item.genres.prefix(1)))
            let ranked = channelIndices.sorted { lhs, rhs in
                let leftFit = fit(channels[lhs], primary: primary), rightFit = fit(channels[rhs], primary: primary)
                if leftFit != rightFit { return leftFit > rightFit }
                let leftRank = Self.sourceRank[channels[lhs].definition.source] ?? .max
                let rightRank = Self.sourceRank[channels[rhs].definition.source] ?? .max
                if leftRank != rightRank { return leftRank < rightRank }
                return sizes[lhs] != sizes[rhs] ? sizes[lhs] < sizes[rhs] : lhs < rhs
            }
            for index in diversified(ranked, channels: channels, limit: limit) {
                allowed[index, default: []].insert(title)
            }
        }
        return channels.enumerated().map { index, channel in
            let keep = allowed[index] ?? []
            return (channel.definition, channel.items.filter { keep.contains(Self.title(of: $0)) })
        }
    }

    /// Puts any title left without a themed channel back on the first surviving
    /// channel it originally fit.
    private func restoringOrphans(_ assigned: [Resolved], candidates: [Resolved]) -> [Resolved] {
        var result = assigned
        let placed = Set(assigned.flatMap { titles(of: $0.items) })
        let positions = Dictionary(uniqueKeysWithValues: result.enumerated().map { ($0.element.definition.id, $0.offset) })
        for candidate in candidates {
            guard let position = positions[candidate.definition.id] else { continue }
            let orphans = candidate.items.filter { !placed.contains(Self.title(of: $0)) }
            let alreadyAdded = titles(of: result[position].items)
            result[position].items += orphans.filter { !alreadyAdded.contains(Self.title(of: $0)) }
        }
        return result
    }

    /// Up to `limit` channels: the best genre channel and the best decade channel
    /// first, so a show lands on both rather than on three similar genre
    /// channels; then the next best overall (networks and collections only fill
    /// what's left).
    private func diversified(_ ranked: [Int], channels: [Resolved], limit: Int) -> [Int] {
        var chosen: [Int] = []
        var usedSources = Set<ChannelSource>()
        for index in ranked where chosen.count < limit {
            let source = channels[index].definition.source
            if Self.guaranteedSources.contains(source) && usedSources.insert(source).inserted {
                chosen.append(index)
            }
        }
        for index in ranked where chosen.count < limit && !chosen.contains(index) {
            chosen.append(index)
        }
        return chosen
    }

    /// 1 when the channel is built around the title's main genre.
    private func fit(_ channel: Resolved, primary: Set<GenreCategory>) -> Int {
        channel.definition.rule.categories.isDisjoint(with: primary) ? 0 : 1
    }

    // MARK: - Titles

    private static func title(of item: MediaItem) -> String {
        item.seriesID ?? item.id
    }

    private func titles(of items: [MediaItem]) -> Set<String> {
        Set(items.map(Self.title))
    }

    private func titleItems(of items: [MediaItem]) -> [String: MediaItem] {
        var result: [String: MediaItem] = [:]
        for item in items where result[Self.title(of: item)] == nil {
            result[Self.title(of: item)] = item
        }
        return result
    }
}
