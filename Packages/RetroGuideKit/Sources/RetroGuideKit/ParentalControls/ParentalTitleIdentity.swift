import Foundation

/// A show or movie across servers. Names are display text, never matching evidence.
public struct ParentalTitleIdentity: Codable, Hashable, Sendable {
    public let kind: MediaKind
    public let name: String
    public let year: Int?
    public private(set) var sourceIDs: Set<String>
    public private(set) var identifiers: [String: Set<String>]

    public init(item: MediaItem) {
        kind = item.kind
        name = item.headline
        year = item.kind == .movie ? item.year : nil
        sourceIDs = [item.seriesID ?? item.id]
        identifiers = [:]
        let ids = item.kind == .episode ? item.titleIDs : (item.publicIDs ?? item.titleIDs)
        for (provider, value) in [("imdb", ids?.imdb), ("tmdb", ids?.tmdb), ("tvdb", ids?.tvdb)] {
            if let value { identifiers[provider] = [String(value)] }
        }
        let external = item.kind == .episode ? item.series?.externalID : item.externalID
        if let external {
            identifiers["external"] = [external]
            if let url = URL(string: external), let provider = url.scheme,
               ["imdb", "tmdb", "tvdb"].contains(provider) {
                let raw = url.path.isEmpty ? url.host : url.lastPathComponent
                if let raw, let value = UInt32(provider == "imdb" ? raw.replacingOccurrences(of: "tt", with: "") : raw) {
                    identifiers[provider, default: []].insert(String(value))
                }
            }
        }
    }

    /// The same title with compatible metadata. A conflicting database id cannot grant access.
    public func matches(_ other: Self, blocking: Bool = false) -> Bool {
        guard kind == other.kind else { return false }
        let sharesSource = !sourceIDs.isDisjoint(with: other.sourceIDs)
        let sharesIdentifier = identifiers.contains { provider, values in
            !values.isDisjoint(with: other.identifiers[provider] ?? [])
        }
        guard sharesSource || sharesIdentifier else { return false }
        if blocking { return true }
        return identifiers.allSatisfy { provider, values in
            // Plex and Jellyfin can use different external-id schemes for the same title.
            guard provider != "external", let others = other.identifiers[provider] else { return true }
            return values == others
        }
    }

    func merging(_ other: Self) -> Self {
        var result = self
        result.sourceIDs.formUnion(other.sourceIDs)
        result.identifiers.merge(other.identifiers) { $0.union($1) }
        return result
    }

    var lookupKeys: Set<String> {
        var keys = Set(sourceIDs.map { "source/\($0)" })
        for (provider, values) in identifiers {
            keys.formUnion(values.map { "\(kind.rawValue)/\(provider)/\($0)" })
        }
        return keys
    }
}
