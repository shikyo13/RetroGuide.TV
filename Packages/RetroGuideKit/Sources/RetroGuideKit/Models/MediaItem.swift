import Foundation

/// A single schedulable piece of media (a movie or an episode) from any server.
///
/// Items are value types that are cached to disk, so they only carry the
/// metadata RetroGuide needs for scheduling and display.
public struct MediaItem: Codable, Sendable, Identifiable {
    /// Globally unique identifier: `"<serverID>/<itemKey>"`.
    public let id: String
    public let serverID: String
    /// The server's native identifier for the item (Plex `ratingKey`).
    public let itemKey: String
    /// A server-independent identifier (e.g. Plex's `plex://episode/…` guid) used to
    /// recognize the same title on different servers. `nil` when only local ids exist.
    public let externalID: String?
    public let libraryID: String
    public let kind: MediaKind
    public let title: String
    public let series: SeriesInfo?
    public let year: Int?
    public let duration: TimeInterval
    public let summary: String?
    public let contentRating: String?
    public let audience: Audience
    public let genres: [String]
    public let networks: [String]
    public let collections: [String]
    /// Production countries (show-level for episodes).
    public let countries: [String]
    public let artwork: Artwork
    /// Every version of the file on its server, in the server's order.
    public let versions: [MediaVersion]
    /// The title's public database ids (the show's for an episode).
    public let titleIDs: TitleIDs?
    /// The item's own public database ids (the episode's, not its show's).
    /// Servers name items differently (Plex's `plex://` guids, Jellyfin's
    /// own ids); these recognize the same movie or episode on both.
    public let publicIDs: TitleIDs?
    /// When the item was added to its server (the earliest copy's, once
    /// merged). Schedules bring new items in from the next broadcast day
    /// after this (see ``ContentVersions``); `nil` counts as always there.
    public let addedAt: Date?
    /// Other libraries (on any server) holding a copy of this episode or
    /// movie that lost out to this one when copies were merged: the item is
    /// still part of those libraries. Set only in the merged library index.
    public private(set) var otherLibraryIDs: [String]?

    public init(
        serverID: String,
        itemKey: String,
        externalID: String? = nil,
        libraryID: String,
        kind: MediaKind,
        title: String,
        series: SeriesInfo? = nil,
        year: Int? = nil,
        duration: TimeInterval,
        summary: String? = nil,
        contentRating: String? = nil,
        audience: Audience = .unrated,
        genres: [String] = [],
        networks: [String] = [],
        collections: [String] = [],
        countries: [String] = [],
        artwork: Artwork = Artwork(),
        versions: [MediaVersion] = [],
        titleIDs: TitleIDs? = nil,
        publicIDs: TitleIDs? = nil,
        addedAt: Date? = nil
    ) {
        self.id = Self.makeID(serverID: serverID, itemKey: itemKey)
        self.serverID = serverID
        self.itemKey = itemKey
        self.externalID = externalID
        self.libraryID = libraryID
        self.kind = kind
        self.title = title
        self.series = series
        self.year = year
        self.duration = duration
        self.summary = summary
        self.contentRating = contentRating
        self.audience = audience
        self.genres = genres
        self.networks = networks
        self.collections = collections
        self.countries = countries
        self.artwork = artwork
        self.versions = versions
        self.titleIDs = titleIDs
        self.publicIDs = publicIDs
        self.addedAt = addedAt
    }

    /// Every library holding a copy of this item.
    public var libraryIDs: [String] {
        [libraryID] + (otherLibraryIDs ?? [])
    }

    /// This item, also counting as part of the libraries and collections the
    /// other copies of it belong to.
    func merging(copies: [MediaItem]) -> MediaItem {
        let libraries = copies.flatMap(\.libraryIDs).filter { $0 != libraryID }
        let otherCollections = copies.flatMap(\.collections).filter { !collections.contains($0) }
        let borrowedIDs = (titleIDs == nil && copies.contains { $0.titleIDs != nil })
            || (publicIDs == nil && copies.contains { $0.publicIDs != nil })
        let earliest = ([addedAt] + copies.map(\.addedAt)).compactMap { $0 }.min()
        guard !libraries.isEmpty || !otherCollections.isEmpty || borrowedIDs || earliest != addedAt else { return self }
        var merged = MediaItem(
            serverID: serverID, itemKey: itemKey, externalID: externalID, libraryID: libraryID, kind: kind, title: title,
            series: series, year: year, duration: duration, summary: summary, contentRating: contentRating, audience: audience,
            genres: genres, networks: networks, collections: collections + Set(otherCollections).sorted(), countries: countries,
            artwork: artwork, versions: versions, titleIDs: titleIDs ?? copies.lazy.compactMap(\.titleIDs).first,
            publicIDs: publicIDs ?? copies.lazy.compactMap(\.publicIDs).first, addedAt: earliest
        )
        merged.otherLibraryIDs = Set(libraries).sorted()
        return merged
    }

    /// This item as if it had been added to its server at `date`.
    func withAddedAt(_ date: Date?) -> MediaItem {
        var copy = MediaItem(
            serverID: serverID, itemKey: itemKey, externalID: externalID, libraryID: libraryID, kind: kind, title: title,
            series: series, year: year, duration: duration, summary: summary, contentRating: contentRating, audience: audience,
            genres: genres, networks: networks, collections: collections, countries: countries, artwork: artwork,
            versions: versions, titleIDs: titleIDs, publicIDs: publicIDs, addedAt: date
        )
        copy.otherLibraryIDs = otherLibraryIDs
        return copy
    }

    /// This item as part of the show with the shared id `showID`.
    func withShowExternalID(_ showID: String) -> MediaItem {
        guard let series, series.externalID != showID else { return self }
        return MediaItem(
            serverID: serverID, itemKey: itemKey, externalID: externalID, libraryID: libraryID, kind: kind, title: title,
            series: SeriesInfo(key: series.key, title: series.title, seasonNumber: series.seasonNumber, episodeNumber: series.episodeNumber, externalID: showID),
            year: year, duration: duration, summary: summary, contentRating: contentRating, audience: audience, genres: genres,
            networks: networks, collections: collections, countries: countries, artwork: artwork, versions: versions,
            titleIDs: titleIDs, publicIDs: publicIDs, addedAt: addedAt
        )
    }

    public static func makeID(serverID: String, itemKey: String) -> String {
        "\(serverID)/\(itemKey)"
    }
}

// MARK: - Identity-based equality (items are immutable snapshots keyed by id)

extension MediaItem: Hashable {
    public static func == (lhs: MediaItem, rhs: MediaItem) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Display helpers

public extension MediaItem {
    /// The headline shown in the guide: the show name for episodes, the title for movies.
    var headline: String {
        series?.title ?? title
    }

    /// Globally unique series identifier (`"<serverID>/<seriesKey>"`), used by channel rules.
    var seriesID: String? {
        series.map { Self.makeID(serverID: serverID, itemKey: $0.key) }
    }

    /// The show (or, for a movie, the movie itself) this item belongs to, the
    /// same on every server when the server knows the show's global id. Lineups
    /// and schedules group by this.
    var showID: String {
        guard let series else { return id }
        return series.externalID ?? Self.makeID(serverID: serverID, itemKey: series.key)
    }

    /// Secondary line, e.g. `"S2 E5 · The One With the Thing"` or `"1994"`.
    var subheadline: String? {
        switch kind {
        case .episode:
            guard let series else { return title }
            let code = series.episodeCode
            return code.isEmpty ? title : "\(code) · \(title)"
        case .movie:
            return year.map(String.init)
        }
    }
}
