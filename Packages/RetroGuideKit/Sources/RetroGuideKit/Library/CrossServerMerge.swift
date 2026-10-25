import Foundation

/// Combines several servers' libraries: the same episode or movie is kept once
/// (from the highest-priority server, the copy best matching its quality
/// setting), and a show split across servers becomes one show.
///
/// Copies are the same item when they share a global id or a public database
/// id (IMDb, TMDB, TVDB: the only ids Plex and Jellyfin have in common), or
/// when they're the same episode number of the same show. Shows are the same
/// show when they share an episode or a public show id. A server that doesn't
/// know a show's global id learns it from the shows linked to it. Titles alone
/// are never trusted: remakes share names.
struct CrossServerMerge {
    let items: [MediaItem]
    /// Every server's own show id (kept copies or not) → the show's shared id,
    /// so rules naming a show by either id keep matching.
    let showAliases: [String: String]

    init(snapshots: [LibrarySnapshot], quality: [String: VideoQuality]) {
        let entries = snapshots.enumerated().flatMap { priority, snapshot in
            snapshot.items.map { (priority: priority, preference: quality[snapshot.serverID] ?? .original, item: $0) }
        }
        let ambiguous = Self.ambiguousPublicKeys(entries.map(\.item))
        // Read before shows take their shared ids: how widely each copy's own ids are recognized.
        let ranks = Dictionary(entries.map { ($0.item.id, DescriptionRank($0.item)) }, uniquingKeysWith: { first, _ in first })
        let shows = Self.sharedShowIDs(entries.map(\.item), ambiguous: ambiguous)
        let resolved = entries.map { entry in
            (entry.priority, entry.preference, entry.item.seriesID.flatMap { shows[$0] }.map { entry.item.withShowExternalID($0) } ?? entry.item)
        }
        var aliases: [String: String] = [:]
        for (_, _, item) in resolved {
            if let native = item.seriesID {
                aliases[native] = item.showID
            }
        }
        showAliases = aliases
        let copies = Self.bestCopies(resolved, ambiguous: ambiguous, ranks: ranks)
        items = Self.withSharedShowDescriptions(copies, allCopies: resolved.map(\.2), ranks: ranks)
    }

    // MARK: - Shows

    /// The shared id of every server-specific show that has or can learn one.
    ///
    /// Server-specific shows linked by an episode they share or a public show
    /// id (directly or through a chain of servers) are one show. A group whose
    /// linked shows know one shared id per kind of id takes the most widely
    /// shared one (`plex://` beats `tvdb://`, which beats TMDB and IMDb); a
    /// group with two different ids of one kind is left as it is rather than
    /// guessed. The result never depends on the order items or servers are
    /// listed in.
    private static func sharedShowIDs(_ items: [MediaItem], ambiguous: Set<String>) -> [String: String] {
        var known: [String: String] = [:]
        for item in items.sorted(by: { $0.id < $1.id }) {
            if let native = item.seriesID, let shared = item.series?.externalID, known[native] == nil {
                known[native] = shared
            }
        }
        var natives: [String] = []
        var position: [String: Int] = [:]
        for native in Set(items.compactMap(\.seriesID)).sorted() {
            position[native] = natives.count
            natives.append(native)
        }
        var groups = DisjointSets(count: natives.count)
        var firstShowWithKey: [String: Int] = [:]
        for item in items {
            guard let native = item.seriesID, let show = position[native] else { continue }
            for key in sameTitleKeys(of: item, ambiguous: ambiguous) + showKeys(of: item) {
                if let first = firstShowWithKey[key] {
                    groups.union(first, show)
                } else {
                    firstShowWithKey[key] = show
                }
            }
        }
        var sharedIDsByGroup: [Int: Set<String>] = [:]
        for (index, native) in natives.enumerated() {
            if let shared = known[native] {
                sharedIDsByGroup[groups.find(index), default: []].insert(shared)
            }
        }
        for (index, native) in natives.enumerated() {
            if let ids = sharedIDsByGroup[groups.find(index)], let shared = canonicalShowID(ids) {
                known[native] = shared
            }
        }
        return known
    }

    /// One id for linked shows that know `ids`, or `nil` when two of them are
    /// different ids of the same kind, which means the link is doubtful.
    private static func canonicalShowID(_ ids: Set<String>) -> String? {
        let kinds = Dictionary(grouping: ids, by: Key.scheme)
        guard kinds.values.allSatisfy({ $0.count == 1 }) else { return nil }
        return ids.min { (Key.rank(of: $0), $0) < (Key.rank(of: $1), $1) }
    }

    /// The show's public database ids, which every episode of it carries.
    private static func showKeys(of item: MediaItem) -> [String] {
        guard item.series != nil, let ids = item.titleIDs else { return [] }
        return Key.publicKeys(ids, kind: Key.show)
    }

    // MARK: - Copies

    /// Groups each server's copies as if it were the only server, then joins
    /// groups across servers, by id before episode number. A join never puts
    /// two of one server's titles together, so adding a server can't fold
    /// another server's library smaller, whatever its episode numbering.
    private static func bestCopies(
        _ entries: [(priority: Int, preference: VideoQuality, item: MediaItem)],
        ambiguous: Set<String>,
        ranks: [String: DescriptionRank]
    ) -> [MediaItem] {
        let passes: [(MediaItem) -> [String]] = [{ sameTitleKeys(of: $0, ambiguous: ambiguous) }, episodeNumberKeys]
        // Copies are paired in id order, not server order, so the same copies
        // pair up whichever server is listed first.
        let byID = entries.indices.sorted { entries[$0].item.id < entries[$1].item.id }
        var groups = DisjointSets(count: entries.count)
        var firstOnServer: [String: Int] = [:]
        for position in byID {
            let entry = entries[position]
            for key in passes.flatMap({ $0(entry.item) }) {
                let scoped = Key.onServer(key, entry.item.serverID)
                if let first = firstOnServer[scoped] {
                    groups.union(first, position)
                } else {
                    firstOnServer[scoped] = position
                }
            }
        }
        var servers: [Int: Set<String>] = [:]
        for position in entries.indices {
            servers[groups.find(position), default: []].insert(entries[position].item.serverID)
        }
        for keys in passes {
            var firstWithKey: [String: Int] = [:]
            for position in byID {
                for key in keys(entries[position].item) {
                    guard let first = firstWithKey[key] else {
                        firstWithKey[key] = position
                        continue
                    }
                    let (one, other) = (groups.find(first), groups.find(position))
                    let joined = servers[one, default: []].union(servers[other, default: []])
                    guard one != other, joined.count == servers[one, default: []].count + servers[other, default: []].count else { continue }
                    groups.union(one, other)
                    servers[groups.find(one)] = joined
                }
            }
        }
        var best: [Int: Int] = [:]
        var members: [Int: [Int]] = [:]
        for position in entries.indices {
            let group = groups.find(position)
            members[group, default: []].append(position)
            guard let current = best[group] else {
                best[group] = position
                continue
            }
            if isPreferred(entries[position], over: entries[current]) {
                best[group] = position
            }
        }
        // One copy plays, described by the most widely recognized copy; the
        // others' libraries and collections still count.
        return best.sorted { $0.value < $1.value }.map { group, winner in
            let others = (members[group] ?? []).filter { $0 != winner }.map { entries[$0].item }
            guard !others.isEmpty else { return entries[winner].item }
            let playing = entries[winner].item
            let sources = ([playing] + others).sorted { ranks[$0.id, default: .unknown] < ranks[$1.id, default: .unknown] }
            return playing.described(by: sources).merging(copies: others)
        }
    }

    /// Gives every episode of a show found on more than one server the show
    /// details (name, genres, networks) of the copy whose show id is the most
    /// widely recognized, whichever server each episode plays from.
    private static func withSharedShowDescriptions(
        _ items: [MediaItem],
        allCopies: [MediaItem],
        ranks: [String: DescriptionRank]
    ) -> [MediaItem] {
        var describer: [String: MediaItem] = [:]
        var servers: [String: Set<String>] = [:]
        for copy in allCopies where copy.series != nil {
            servers[copy.showID, default: []].insert(copy.serverID)
            if let current = describer[copy.showID], !(ranks[copy.id, default: .unknown].show < ranks[current.id, default: .unknown].show) {
                continue
            }
            describer[copy.showID] = copy
        }
        return items.map { item in
            guard item.series != nil, servers[item.showID, default: []].count > 1, let show = describer[item.showID] else { return item }
            return item.withShowDescription(of: show)
        }
    }

    /// The episode's number within its show (by the show's shared id).
    private static func episodeNumberKeys(of item: MediaItem) -> [String] {
        guard let series = item.series, let show = series.externalID, let season = series.seasonNumber, let episode = series.episodeNumber else {
            return []
        }
        return ["\(show)#\(season)x\(episode)"]
    }

    /// Ids naming exactly this movie or episode on any server: its global id
    /// and its public database ids, unless its server gives one of those to
    /// several items (bad metadata that would otherwise fold them into one).
    private static func sameTitleKeys(of item: MediaItem, ambiguous: Set<String>) -> [String] {
        var keys = item.externalID.map { [$0] } ?? []
        if let ids = item.publicIDs {
            keys += Key.publicKeys(ids, kind: item.kind.rawValue).filter { !ambiguous.contains(Key.onServer($0, item.serverID)) }
        }
        return keys
    }

    /// Public ids (as ``Key/onServer(_:_:)``) that more than one title on the
    /// same server claims. Copies sharing a global id (a movie in two
    /// libraries) are one title, not a conflict.
    private static func ambiguousPublicKeys(_ items: [MediaItem]) -> Set<String> {
        var claimedBy: [String: String] = [:]
        var repeated: Set<String> = []
        for item in items {
            guard let ids = item.publicIDs else { continue }
            let title = item.externalID ?? item.id
            for key in Key.publicKeys(ids, kind: item.kind.rawValue) {
                let scoped = Key.onServer(key, item.serverID)
                if let owner = claimedBy[scoped], owner != title {
                    repeated.insert(scoped)
                } else {
                    claimedBy[scoped] = title
                }
            }
        }
        return repeated
    }

    /// A copy long enough to schedule first (one server may list only a
    /// short clip of the title); then the higher-priority server; on one
    /// server the copy that best fits its quality setting; otherwise the
    /// lower id, so the choice never depends on listing order.
    private static func isPreferred(
        _ candidate: (priority: Int, preference: VideoQuality, item: MediaItem),
        over current: (priority: Int, preference: VideoQuality, item: MediaItem)
    ) -> Bool {
        let (candidateAirs, currentAirs) = (isSchedulable(candidate.item), isSchedulable(current.item))
        if candidateAirs != currentAirs {
            return candidateAirs
        }
        if candidate.priority != current.priority {
            return candidate.priority < current.priority
        }
        if isBetterFit(candidate.item, than: current.item, for: candidate.preference) {
            return true
        }
        if isBetterFit(current.item, than: candidate.item, for: candidate.preference) {
            return false
        }
        return candidate.item.id < current.item.id
    }

    private static func isSchedulable(_ item: MediaItem) -> Bool {
        item.duration >= ScheduleConstants.minimumProgramDuration
    }

    private static func isBetterFit(_ candidate: MediaItem, than current: MediaItem, for quality: VideoQuality) -> Bool {
        guard let candidateVersion = MediaVersionSelector.best(of: candidate.versions, for: quality),
              let currentVersion = MediaVersionSelector.best(of: current.versions, for: quality)
        else { return false }
        return MediaVersionSelector.best(of: [currentVersion, candidateVersion], for: quality) == candidateVersion
            && candidateVersion != currentVersion
    }
}

/// How widely a copy's own ids are recognized, for choosing whose description
/// a merged title takes: by the title's id, then its show's (or for a show,
/// the other way round), then by item id. Server order never counts, so the
/// choice is the same whichever server is listed first.
private struct DescriptionRank: Comparable {
    static let unknown = DescriptionRank(title: Key.unrankedID + 1, show: Key.unrankedID + 1, id: "")

    let title: (Int, Int, String)
    let show: (Int, Int, String)

    init(_ item: MediaItem) {
        self.init(
            title: item.externalID.map(Key.rank(of:)) ?? Key.unrankedID,
            show: item.series?.externalID.map(Key.rank(of:)) ?? Key.unrankedID,
            id: item.id
        )
    }

    private init(title: Int, show: Int, id: String) {
        self.title = (title, show, id)
        self.show = (show, title, id)
    }

    static func < (lhs: DescriptionRank, rhs: DescriptionRank) -> Bool {
        lhs.title < rhs.title
    }

    static func == (lhs: DescriptionRank, rhs: DescriptionRank) -> Bool {
        lhs.title == rhs.title
    }
}

/// How public ids and shared show ids are compared.
private enum Key {
    static let show = "show"
    private static let separator = "/"
    private static let schemeEnd = "://"
    /// Kinds of shared show id, most widely shared first.
    private static let schemeOrder = ["plex", "tvdb", "tmdb", "imdb"]

    /// `ids` qualified by `kind`: TMDB and TVDB number movies, shows and
    /// episodes separately, so a number alone names nothing.
    static func publicKeys(_ ids: TitleIDs, kind: String) -> [String] {
        [("imdb", ids.imdb), ("tmdb", ids.tmdb), ("tvdb", ids.tvdb)].compactMap { name, value in
            value.map { [kind, name, String($0)].joined(separator: separator) }
        }
    }

    static func onServer(_ key: String, _ serverID: String) -> String {
        serverID + separator + key
    }

    /// `plex` for `plex://show/…`, `tmdb` for `tmdb://tv/…`.
    static func scheme(_ id: String) -> String {
        id.range(of: schemeEnd).map { String(id[..<$0.lowerBound]) } ?? id
    }

    static func rank(of id: String) -> Int {
        schemeOrder.firstIndex(of: scheme(id)) ?? schemeOrder.count
    }

    /// The rank of a title or show with no shared id at all.
    static let unrankedID = schemeOrder.count + 1
}

/// Union-find over positions.
private struct DisjointSets {
    private var parent: [Int]

    init(count: Int) {
        parent = Array(0..<count)
    }

    mutating func find(_ element: Int) -> Int {
        var root = element
        while parent[root] != root {
            root = parent[root]
        }
        var node = element
        while parent[node] != root {
            let next = parent[node]
            parent[node] = root
            node = next
        }
        return root
    }

    mutating func union(_ first: Int, _ second: Int) {
        let (a, b) = (find(first), find(second))
        if a != b {
            parent[max(a, b)] = min(a, b)
        }
    }
}
