import Foundation

/// Combines several servers' libraries: the same episode or movie is kept once
/// (from the highest-priority server, the copy best matching its quality
/// setting), and a show split across servers becomes one show.
///
/// Copies are the same item when they share a global id, or when they're the
/// same episode number of the same show. A server that doesn't know a show's
/// global id learns it from episodes it shares with a server that does. Titles
/// alone are never trusted: remakes share names.
struct CrossServerMerge {
    let items: [MediaItem]
    /// Every server's own show id (kept copies or not) → the show's shared id,
    /// so rules naming a show by either id keep matching.
    let showAliases: [String: String]

    init(snapshots: [LibrarySnapshot], quality: [String: VideoQuality]) {
        let entries = snapshots.enumerated().flatMap { priority, snapshot in
            snapshot.items.map { (priority: priority, preference: quality[snapshot.serverID] ?? .original, item: $0) }
        }
        let shows = Self.sharedShowIDs(entries.map(\.item))
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
        items = Self.bestCopies(resolved)
    }

    // MARK: - Shows

    /// The shared id of every server-specific show that has or can learn one.
    private static func sharedShowIDs(_ items: [MediaItem]) -> [String: String] {
        var known: [String: String] = [:]
        for item in items.sorted(by: { $0.id < $1.id }) {
            if let native = item.seriesID, let shared = item.series?.externalID, known[native] == nil {
                known[native] = shared
            }
        }
        // Shows without one borrow it through an episode both servers have.
        var showsByEpisode: [String: Set<String>] = [:]
        for item in items {
            if let episode = item.externalID, let native = item.seriesID {
                showsByEpisode[episode, default: []].insert(native)
            }
        }
        for natives in showsByEpisode.values where natives.count > 1 {
            guard let shared = natives.sorted().compactMap({ known[$0] }).first else { continue }
            for native in natives where known[native] == nil {
                known[native] = shared
            }
        }
        return known
    }

    // MARK: - Copies

    private static func bestCopies(_ entries: [(priority: Int, preference: VideoQuality, item: MediaItem)]) -> [MediaItem] {
        var groups = DisjointSets(count: entries.count)
        var firstWithKey: [String: Int] = [:]
        for (position, entry) in entries.enumerated() {
            for key in duplicateKeys(of: entry.item) {
                if let first = firstWithKey[key] {
                    groups.union(first, position)
                } else {
                    firstWithKey[key] = position
                }
            }
        }
        var best: [Int: Int] = [:]
        for position in entries.indices {
            let group = groups.find(position)
            guard let current = best[group] else {
                best[group] = position
                continue
            }
            if isPreferred(entries[position], over: entries[current]) {
                best[group] = position
            }
        }
        return best.values.sorted().map { entries[$0].item }
    }

    /// Ids under which another server's copy would be found.
    private static func duplicateKeys(of item: MediaItem) -> [String] {
        var keys: [String] = []
        if let externalID = item.externalID {
            keys.append(externalID)
        }
        if let series = item.series, let show = series.externalID, let season = series.seasonNumber, let episode = series.episodeNumber {
            keys.append("\(show)#\(season)x\(episode)")
        }
        return keys
    }

    /// Higher-priority server first; on one server the copy that best fits
    /// its quality setting; otherwise the lower id, so the choice never
    /// depends on listing order.
    private static func isPreferred(
        _ candidate: (priority: Int, preference: VideoQuality, item: MediaItem),
        over current: (priority: Int, preference: VideoQuality, item: MediaItem)
    ) -> Bool {
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

    private static func isBetterFit(_ candidate: MediaItem, than current: MediaItem, for quality: VideoQuality) -> Bool {
        guard let candidateVersion = MediaVersionSelector.best(of: candidate.versions, for: quality),
              let currentVersion = MediaVersionSelector.best(of: current.versions, for: quality)
        else { return false }
        return MediaVersionSelector.best(of: [currentVersion, candidateVersion], for: quality) == candidateVersion
            && candidateVersion != currentVersion
    }
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
