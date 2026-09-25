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
    public let playback: PlaybackInfo?

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
        playback: PlaybackInfo? = nil
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
        self.playback = playback
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
