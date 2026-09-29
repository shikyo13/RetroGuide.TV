import Foundation

/// Gives every title exactly one home channel, sized to the library.
///
/// 1. **Fit:** each title goes to the home theme that matches its most
///    *distinctive* genre in this library (a rare genre like "crime" says more
///    about a show than a common one like "drama"), ties to the catalog order.
/// 2. **Merge:** themes too thin to stay fresh fold into their family
///    (Prime Time, Real TV…); thin families fold into the biggest family of the
///    same kind.
/// 3. **Split:** themes big enough for several channels split by era.
struct HomePlanner {
    struct Planned {
        var definition: ChannelDefinition
        var titles: [TitleCatalog.Title]
        var isShowChannel: Bool { titles.contains(where: \.isShow) }
        var hours: Double { titles.reduce(0) { $0 + $1.hours } }
    }

    enum Tuning {
        /// A show channel should run this long before any episode comes round again…
        static let freshnessDays = 14.0
        static var freshHours: Double { freshnessDays * 24 }
        /// …while movie channels, like real ones, can bring a film back after a week.
        static let movieFreshnessDays = 7.0
        /// Home channels never outnumber this; beyond it channels grow instead.
        static let maximumHomeChannels = 60
        /// Small libraries still get about this many home channels.
        static let minimumHomeChannels = 6
        /// A theme splits by era into at most this many channels.
        static let maximumEraParts = 4
    }

    let themes: [ChannelTheme]

    /// How much content a home channel should hold, and the least it may hold.
    struct Sizing {
        let target: Double
        let merge: Double

        init(totalHours: Double, freshnessDays: Double) {
            target = max(freshnessDays * 24, totalHours / Double(Tuning.maximumHomeChannels))
            merge = min(target, totalHours / Double(Tuning.minimumHomeChannels))
        }
    }

    func plan(_ catalog: TitleCatalog, index: LibraryIndex) -> [Planned] {
        let totalHours = catalog.titles.reduce(0) { $0 + $1.hours }
        guard totalHours > 0 else { return [] }
        let shows = Sizing(totalHours: totalHours, freshnessDays: Tuning.freshnessDays)
        let movies = Sizing(totalHours: totalHours, freshnessDays: Tuning.movieFreshnessDays)
        let sizing: ([TitleCatalog.Title]) -> Sizing = { titles in titles.contains(where: \.isShow) ? shows : movies }

        let homes = themes.filter { $0.role == .home }
        var byTheme: [String: [TitleCatalog.Title]] = [:]
        var byFamily: [ChannelTheme.Family: [TitleCatalog.Title]] = [:]
        let scorer = FitScorer(catalog: catalog, index: index, themes: homes)
        for title in catalog.titles {
            if let theme = scorer.bestTheme(for: title) {
                byTheme[theme.definition.id, default: []].append(title)
            } else {
                byFamily[Self.fallbackFamily(for: title), default: []].append(title)
            }
        }

        var planned: [Planned] = []
        for theme in homes {
            guard let titles = byTheme[theme.definition.id] else { continue }
            let hours = titles.reduce(0) { $0 + $1.hours }
            if hours < sizing(titles).merge, let family = theme.family {
                // Each title joins the family of what it is: movies to movies,
                // anime and cartoons to theirs, everything else to the theme's.
                for title in titles {
                    let own = Self.fallbackFamily(for: title)
                    let target = !title.isShow || [.anime, .cartoons].contains(own) || family == .movies ? own : family
                    byFamily[target, default: []].append(title)
                }
            } else {
                planned += Self.split(Planned(definition: theme.definition, titles: titles), targetHours: sizing(titles).target)
            }
        }
        planned += families(byFamily, sizing: sizing)
        return planned
    }

    /// Family channels for merged titles; a family too thin to stand alone
    /// joins the biggest family of the same kind (shows or movies).
    private func families(_ groups: [ChannelTheme.Family: [TitleCatalog.Title]], sizing: ([TitleCatalog.Title]) -> Sizing) -> [Planned] {
        var groups = groups
        for isShow in [true, false] {
            let kind = ChannelTheme.Family.allCases.filter { ($0 == .movies) != isShow && groups[$0] != nil }
            guard let biggest = kind.max(by: { hours(groups[$0]) < hours(groups[$1]) }) else { continue }
            for family in kind where family != biggest && hours(groups[family]) < sizing(groups[family] ?? []).merge {
                groups[biggest, default: []] += groups[family] ?? []
                groups[family] = nil
            }
        }
        return ChannelTheme.Family.allCases.flatMap { family -> [Planned] in
            guard let titles = groups[family], !titles.isEmpty else { return [] }
            return Self.split(Planned(definition: family.definition, titles: titles), targetHours: sizing(titles).target)
        }
    }

    private func hours(_ titles: [TitleCatalog.Title]?) -> Double {
        (titles ?? []).reduce(0) { $0 + $1.hours }
    }

    private static func fallbackFamily(for title: TitleCatalog.Title) -> ChannelTheme.Family {
        guard title.isShow else { return .movies }
        if title.categories.contains(.anime) { return .anime }
        if title.categories.contains(.animation) || title.categories.contains(.children) { return .cartoons }
        if !title.categories.isDisjoint(with: unscriptedCategories) { return .unscripted }
        return .scripted
    }

    private static let unscriptedCategories: Set<GenreCategory> = [.documentary, .reality, .gameShow, .talk, .food, .travel, .sport, .music, .news]

    // MARK: - Era splits

    /// Splits a channel with more content than `targetHours` can keep fresh into
    /// era channels ("Laugh Track: 90s"), each holding roughly equal hours.
    static func split(_ channel: Planned, targetHours: Double) -> [Planned] {
        let parts = min(Tuning.maximumEraParts, Int(channel.hours / targetHours))
        guard parts > 1 else { return [channel] }
        let dated = channel.titles.sorted { ($0.decade ?? .max) < ($1.decade ?? .max) }
        let share = channel.hours / Double(parts)
        var groups: [[TitleCatalog.Title]] = [[]]
        var accumulated = 0.0
        var lastDecade: Int?
        for title in dated {
            // Only cut between decades, so a decade never spans two channels.
            if accumulated >= share, groups.count < parts, title.decade != lastDecade {
                groups.append([])
                accumulated = 0
            }
            groups[groups.count - 1].append(title)
            accumulated += title.hours
            lastDecade = title.decade
        }
        // A leftover era too small to stay fresh joins the one before it.
        if groups.count > 1, let last = groups.last, last.reduce(0, { $0 + $1.hours }) < targetHours {
            groups.removeLast()
            groups[groups.count - 1] += last
        }
        guard groups.count > 1 else { return [channel] }
        return groups.map { titles in
            let decades = titles.compactMap(\.decade)
            var definition = channel.definition
            let first = decades.min(), last = decades.max()
            definition.id = "\(channel.definition.id)@\(first ?? .zero)"
            definition.name = "\(channel.definition.name): \(EraLabel.make(from: first, to: last))"
            return Planned(definition: definition, titles: titles)
        }
    }
}

/// "Classics", "80s", "90s–2000s", "Now".
enum EraLabel {
    private static let classicsBefore = 1980
    private static let nowFrom = 2020

    static func make(from first: Int?, to last: Int?) -> String {
        guard let first, let last else { return "Mix" }
        if last < classicsBefore { return "Classics" }
        if first >= nowFrom { return "Now" }
        if first == last { return short(first) }
        return "\(short(first))–\(short(last))"
    }

    private static func short(_ decade: Int) -> String {
        decade >= 2000 ? "\(decade)s" : "\(decade % 100)s"
    }
}

/// Scores how well a title fits each home theme.
private struct FitScorer {
    private let rules: [(theme: ChannelTheme, rule: CompiledRule)]
    private let distinctiveness: [GenreCategory: Double]
    private let index: LibraryIndex
    /// Score for themes defined by something other than genre (audience, keywords).
    private static let baseScore = 1.0

    init(catalog: TitleCatalog, index: LibraryIndex, themes: [ChannelTheme]) {
        self.index = index
        rules = themes.map { ($0, CompiledRule($0.definition.rule)) }
        var counts: [GenreCategory: Int] = [:]
        for title in catalog.titles {
            for category in title.categories {
                counts[category, default: 0] += 1
            }
        }
        let total = Double(catalog.titles.count + 1)
        distinctiveness = counts.mapValues { log(total / Double($0 + 1)) + 1 }
    }

    func bestTheme(for title: TitleCatalog.Title) -> ChannelTheme? {
        let position = title.positions[0]
        let item = index.items[position]
        let matching = rules.filter { $0.rule.matches(item, index.attributes[position]) }
        // Anime is what viewers know a show as, however common it is in the
        // library: an anime about sports belongs with anime, not Sports Desk.
        let animeThemes = matching.filter { $0.theme.definition.rule.categories.contains(.anime) }
        let candidates = title.categories.contains(.anime) && !animeThemes.isEmpty ? animeThemes : matching
        var best: (theme: ChannelTheme, score: Double)?
        for (theme, _) in candidates {
            let shared = theme.definition.rule.categories.intersection(title.categories)
            let score = shared.isEmpty ? Self.baseScore : shared.map { distinctiveness[$0, default: Self.baseScore] }.max() ?? Self.baseScore
            if best == nil || score > (best?.score ?? 0) {
                best = (theme, score)
            }
        }
        return best?.theme
    }
}
