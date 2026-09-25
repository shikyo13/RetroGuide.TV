import Foundation
@testable import RetroGuideKit

/// Builders for concise, readable test data.
enum TestFactory {
    static let serverID = "server"
    static let libraryID = "server/1"
    static let halfHour: TimeInterval = 30 * 60
    static let episodeLength: TimeInterval = 22 * 60

    static func episode(
        _ key: String,
        show: String = "Show",
        season: Int = 1,
        number: Int = 1,
        duration: TimeInterval = episodeLength,
        genres: [String] = [],
        networks: [String] = [],
        rating: String? = nil,
        year: Int? = nil
    ) -> MediaItem {
        MediaItem(
            serverID: serverID,
            itemKey: key,
            libraryID: libraryID,
            kind: .episode,
            title: "\(show) \(key)",
            series: SeriesInfo(key: show.lowercased(), title: show, seasonNumber: season, episodeNumber: number),
            year: year,
            duration: duration,
            contentRating: rating,
            audience: Audience.classify(rating: rating),
            genres: genres,
            networks: networks
        )
    }

    static func movie(_ key: String, duration: TimeInterval = 2 * 3_600, genres: [String] = [], year: Int? = nil) -> MediaItem {
        MediaItem(
            serverID: serverID,
            itemKey: key,
            libraryID: libraryID,
            kind: .movie,
            title: "Movie \(key)",
            year: year,
            duration: duration,
            genres: genres
        )
    }

    /// A show with `count` sequential episodes.
    static func show(_ name: String, episodes count: Int, genres: [String] = []) -> [MediaItem] {
        (1...count).map { episode("\(name)-\($0)", show: name, number: $0, genres: genres) }
    }

    static func timeline(_ items: [MediaItem], ordering: ScheduleOrdering = .shuffle, grid: ScheduleGrid = .continuous) -> ChannelTimeline {
        ChannelTimeline(channelID: "test.channel", items: items, ordering: ordering, grid: grid)
    }
}
