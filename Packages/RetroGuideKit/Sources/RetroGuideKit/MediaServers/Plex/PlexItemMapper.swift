import Foundation

/// Tag memberships gathered from Plex filter endpoints, keyed by `ratingKey`.
/// (List endpoints truncate tags, so these are fetched separately.)
struct PlexTagMemberships: Sendable {
    var genres: [String: [String]] = [:]
    var networks: [String: [String]] = [:]
    var collections: [String: [String]] = [:]
}

/// Converts Plex wire metadata into ``MediaItem`` values.
enum PlexItemMapper {
    static func movie(
        _ metadata: PlexMetadata,
        library: MediaLibrary,
        memberships: PlexTagMemberships
    ) -> MediaItem? {
        guard let duration = seconds(metadata.duration) else { return nil }
        return MediaItem(
            serverID: library.serverID,
            itemKey: metadata.ratingKey,
            externalID: metadata.globalGuid,
            libraryID: library.id,
            kind: .movie,
            title: metadata.title,
            year: metadata.year,
            duration: duration,
            summary: metadata.summary,
            contentRating: metadata.contentRating,
            audience: Audience.classify(rating: metadata.contentRating, age: metadata.contentRatingAge),
            genres: merged(memberships.genres[metadata.ratingKey], metadata.genres),
            networks: [],
            collections: memberships.collections[metadata.ratingKey] ?? [],
            countries: (metadata.countries ?? []).map(\.tag),
            artwork: Artwork(
                poster: metadata.thumb,
                backdrop: metadata.art,
                logo: metadata.clearLogo,
                thumbnail: metadata.thumb
            ),
            playback: metadata.playbackInfo
        )
    }

    static func episode(
        _ metadata: PlexMetadata,
        show: PlexMetadata?,
        library: MediaLibrary,
        memberships: PlexTagMemberships
    ) -> MediaItem? {
        guard let duration = seconds(metadata.duration),
              let showKey = metadata.grandparentRatingKey
        else { return nil }
        let rating = metadata.contentRating ?? show?.contentRating
        let collections = (memberships.collections[showKey] ?? []) + (memberships.collections[metadata.ratingKey] ?? [])
        return MediaItem(
            serverID: library.serverID,
            itemKey: metadata.ratingKey,
            externalID: metadata.globalGuid,
            libraryID: library.id,
            kind: .episode,
            title: metadata.title,
            series: SeriesInfo(
                key: showKey,
                title: metadata.grandparentTitle ?? show?.title ?? metadata.title,
                seasonNumber: metadata.parentIndex,
                episodeNumber: metadata.index
            ),
            year: metadata.year ?? show?.year,
            duration: duration,
            summary: metadata.summary,
            contentRating: rating,
            audience: Audience.classify(rating: rating, age: metadata.contentRatingAge ?? show?.contentRatingAge),
            genres: merged(memberships.genres[showKey], show?.genres),
            networks: memberships.networks[showKey] ?? [],
            collections: Array(Set(collections)).sorted(),
            countries: (show?.countries ?? metadata.countries ?? []).map(\.tag),
            artwork: Artwork(
                poster: metadata.grandparentThumb ?? show?.thumb,
                backdrop: metadata.grandparentArt ?? show?.art ?? metadata.art,
                logo: metadata.clearLogo ?? show?.clearLogo,
                thumbnail: metadata.thumb
            ),
            playback: metadata.playbackInfo
        )
    }

    private static func seconds(_ milliseconds: Int?) -> TimeInterval? {
        guard let milliseconds, milliseconds > .zero else { return nil }
        return TimeInterval(milliseconds) / PlexAPI.Defaults.millisecondsPerSecond
    }

    /// Full membership first, falling back to the (possibly truncated) inline tags.
    private static func merged(_ full: [String]?, _ inline: [PlexTag]?) -> [String] {
        var seen = Set<String>()
        return ((full ?? []) + (inline ?? []).map(\.tag)).filter { seen.insert($0).inserted }
    }
}
