import Foundation

/// A title's ids in the public movie and TV databases: the show's for an
/// episode. Used to look titles up in ``TitleClassification``, whatever
/// server or metadata agent they came from.
public struct TitleIDs: Codable, Sendable, Hashable {
    public var imdb: UInt32?
    public var tmdb: UInt32?
    public var tvdb: UInt32?

    private enum Scheme {
        static let imdb = "imdb://"
        static let tmdb = "tmdb://"
        static let tvdb = "tvdb://"
        /// IMDb title ids are `tt` followed by digits.
        static let imdbTitlePrefix = "tt"
    }

    public init(imdb: UInt32? = nil, tmdb: UInt32? = nil, tvdb: UInt32? = nil) {
        self.imdb = imdb
        self.tmdb = tmdb
        self.tvdb = tvdb
    }

    /// From agent guids such as `imdb://tt0944947`, `tmdb://1399` and
    /// `tvdb://121361`; `nil` when none of them is one of those.
    public init?(guids: [String]) {
        var ids = TitleIDs()
        for guid in guids {
            if guid.hasPrefix(Scheme.imdb) {
                let value = guid.dropFirst(Scheme.imdb.count)
                if value.hasPrefix(Scheme.imdbTitlePrefix) {
                    ids.imdb = UInt32(value.dropFirst(Scheme.imdbTitlePrefix.count))
                }
            } else if guid.hasPrefix(Scheme.tmdb) {
                ids.tmdb = UInt32(guid.dropFirst(Scheme.tmdb.count))
            } else if guid.hasPrefix(Scheme.tvdb) {
                ids.tvdb = UInt32(guid.dropFirst(Scheme.tvdb.count))
            }
        }
        guard !ids.isEmpty else { return nil }
        self = ids
    }

    public var isEmpty: Bool {
        imdb == nil && tmdb == nil && tvdb == nil
    }
}
