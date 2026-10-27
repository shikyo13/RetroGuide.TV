import Foundation

/// Libraries on different servers that are really one library, such as Plex
/// and Jellyfin reading the same folders: the same name and kind, with most
/// of the smaller one's titles also in the other. They're one library in the
/// lineup, one "TV Shows" channel rather than "TV Shows · Plex" and
/// "TV Shows · Jellyfin", named and numbered as before the second server.
struct LibraryTwins: Sendable {
    /// Share of the smaller library's titles the two must have in common.
    static let minimumSharedFraction = 0.8

    /// Every twin's id → the id of its group's first library (on the
    /// highest-priority server). Libraries without a twin aren't listed.
    let canonical: [String: String]
    /// Each group's first library id → every library id in the group.
    let members: [String: Set<String>]

    static let none = LibraryTwins(canonical: [:])

    /// `libraries` in server priority order; `items` merged across servers.
    init(libraries: [MediaLibrary], items: [MediaItem]) {
        var counts: [String: Int] = [:]
        var shared: [String: [String: Int]] = [:]
        for item in items {
            let ids = item.libraryIDs
            ids.forEach { counts[$0, default: .zero] += 1 }
            for one in ids {
                for other in ids where other != one {
                    shared[one, default: [:]][other, default: .zero] += 1
                }
            }
        }
        var canonical: [String: String] = [:]
        var firsts: [MediaLibrary] = []
        for library in libraries {
            let twin = firsts.first { first in
                guard first.serverID != library.serverID, first.kind == library.kind,
                      TextNormalizer.key(first.title) == TextNormalizer.key(library.title)
                else { return false }
                let smaller = min(counts[first.id, default: .zero], counts[library.id, default: .zero])
                let common = shared[first.id]?[library.id] ?? .zero
                return smaller > .zero && Double(common) >= Self.minimumSharedFraction * Double(smaller)
            }
            if let twin {
                canonical[library.id] = twin.id
            } else {
                firsts.append(library)
            }
        }
        self.init(canonical: canonical)
    }

    private init(canonical: [String: String]) {
        self.canonical = canonical
        var members: [String: Set<String>] = [:]
        for (twin, first) in canonical {
            members[first, default: [first]].insert(twin)
        }
        self.members = members
    }

    /// `ids` with every twin of each.
    func expanding(_ ids: Set<String>) -> Set<String> {
        ids.reduce(into: ids) { all, id in
            all.formUnion(members[canonical[id] ?? id] ?? [])
        }
    }
}
