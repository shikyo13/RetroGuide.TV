import Foundation

/// Series context for an episode.
public struct SeriesInfo: Codable, Sendable, Hashable {
    /// Server-native identifier of the show.
    public let key: String
    public let title: String
    public let seasonNumber: Int?
    public let episodeNumber: Int?

    public init(key: String, title: String, seasonNumber: Int?, episodeNumber: Int?) {
        self.key = key
        self.title = title
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
    }

    /// Compact episode code such as `"S3 E12"`; empty when numbering is unknown.
    public var episodeCode: String {
        switch (seasonNumber, episodeNumber) {
        case let (season?, episode?): "S\(season) E\(episode)"
        case let (nil, episode?): "E\(episode)"
        case let (season?, nil): "S\(season)"
        case (nil, nil): ""
        }
    }

    /// Plex files specials, OVAs and extras under season 0.
    private static let specialsSeason = 0

    /// Sort key that keeps episodes in broadcast order within a show, with
    /// specials after the last regular season rather than before episode 1.
    var broadcastOrder: (Int, Int) {
        let season = seasonNumber == Self.specialsSeason ? Int.max : (seasonNumber ?? .zero)
        return (season, episodeNumber ?? .zero)
    }
}
