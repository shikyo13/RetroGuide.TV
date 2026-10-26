import Foundation

/// Lightweight title choices and saved-selection resolution, without building another library index.
public struct ParentalTitleCatalog: Sendable {
    public struct Title: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let year: Int?
        public let serverNames: [String]
        public let identity: ParentalTitleIdentity
    }

    public let titles: [Title]
    private let positionsByKey: [String: Set<Int>]

    public init(snapshots: [LibrarySnapshot]) {
        struct Entry {
            var identity: ParentalTitleIdentity
            let name: String
            let year: Int?
            var servers: Set<String>
        }
        var bySource: [String: Entry] = [:]
        for snapshot in snapshots {
            for item in snapshot.items {
                let source = item.seriesID ?? item.id
                let identity = ParentalTitleIdentity(item: item)
                if var entry = bySource[source] {
                    entry.identity = entry.identity.merging(identity)
                    entry.servers.insert(snapshot.serverName)
                    bySource[source] = entry
                } else {
                    bySource[source] = Entry(identity: identity, name: item.headline,
                        year: item.kind == .movie ? item.year : nil, servers: [snapshot.serverName])
                }
            }
        }
        let entries = bySource.sorted { $0.key < $1.key }.map(\.value)
        var parents = Array(entries.indices)
        var identities = entries.map(\.identity)
        func root(_ position: Int) -> Int {
            var current = position
            while parents[current] != current { current = parents[current] }
            return current
        }
        var candidates: [String: Set<Int>] = [:]
        for position in entries.indices {
            for key in entries[position].identity.lookupKeys.sorted() {
                for prior in (candidates[key] ?? []).sorted() {
                    let a = root(position), b = root(prior)
                    guard a != b, identities[a].matches(identities[b]) else { continue }
                    let winner = min(a, b), loser = max(a, b)
                    parents[loser] = winner
                    identities[winner] = identities[winner].merging(identities[loser])
                }
                candidates[key, default: []].insert(position)
            }
        }
        var servers: [Int: Set<String>] = [:]
        for position in entries.indices { servers[root(position), default: []].formUnion(entries[position].servers) }
        titles = servers.keys.sorted().map { position in
            let identity = identities[position]
            return Title(id: identity.sourceIDs.sorted().first!, name: entries[position].name,
                year: entries[position].year, serverNames: servers[position]!.sorted(), identity: identity)
        }.sorted { ($0.name.localizedLowercase, $0.year ?? .zero, $0.id) < ($1.name.localizedLowercase, $1.year ?? .zero, $1.id) }
        var index: [String: Set<Int>] = [:]
        for (position, title) in titles.enumerated() {
            for key in title.identity.lookupKeys { index[key, default: []].insert(position) }
        }
        positionsByKey = index
    }

    public func selectedIDs(for selections: [ParentalTitleIdentity], legacyIDs: Set<String> = [], blocking: Bool = false) -> Set<String> {
        Set(matchingPositions(selections, legacyIDs: legacyIDs, blocking: blocking).map { titles[$0].id })
    }

    public func identities(for selectedIDs: Set<String>) -> [ParentalTitleIdentity] {
        titles.filter { selectedIDs.contains($0.id) }.map(\.identity)
    }

    public func sourceIDs(for selections: [ParentalTitleIdentity], legacyIDs: Set<String> = [], blocking: Bool = false) -> Set<String> {
        Set(matchingPositions(selections, legacyIDs: legacyIDs, blocking: blocking).flatMap { titles[$0].identity.sourceIDs })
    }

    /// Retains offline choices and remembers newly matched ids for future server changes.
    public func expanding(_ selections: [ParentalTitleIdentity], legacyIDs: Set<String> = [], blocking: Bool = false) -> [ParentalTitleIdentity] {
        let expanded = selections.map { selection in
            matchingPositions([selection], legacyIDs: [], blocking: false).reduce(selection) { $0.merging(titles[$1].identity) }
        }
        var result: [ParentalTitleIdentity] = []
        for identity in expanded {
            if let existing = result.firstIndex(where: { $0.matches(identity) }) {
                result[existing] = result[existing].merging(identity)
            } else { result.append(identity) }
        }
        for position in matchingPositions([], legacyIDs: legacyIDs, blocking: blocking).sorted() {
            let identity = titles[position].identity
            if let existing = result.firstIndex(where: { $0.matches(identity) }) {
                result[existing] = result[existing].merging(identity)
            } else { result.append(identity) }
        }
        return result
    }

    private func matchingPositions(_ selections: [ParentalTitleIdentity], legacyIDs: Set<String>, blocking: Bool) -> Set<Int> {
        var matches = Set(legacyIDs.flatMap { positionsByKey["source/\($0)"] ?? [] })
        for selection in selections {
            let candidates = Set(selection.lookupKeys.flatMap { positionsByKey[$0] ?? [] })
            matches.formUnion(candidates.filter { selection.matches(titles[$0].identity, blocking: blocking) })
        }
        return matches
    }
}
