import Foundation

/// Converts Jellyfin wire items into ``MediaItem`` values.
enum JellyfinItemMapper {
    private enum Scheme {
        static let imdb = "imdb://"
        static let tmdb = "tmdb://"
        static let tvdb = "tvdb://"
        /// TMDB and TVDB number movies, shows and episodes separately, so
        /// their ids only identify a title together with its kind.
        static let tmdbMovie = "tmdb://movie/"
        static let tmdbShow = "tmdb://tv/"
        static let tmdbEpisode = "tmdb://episode/"
        static let tvdbEpisode = "tvdb://episode/"
    }

    static func movie(_ item: JellyfinItem, library: MediaLibrary, collections: [String: [String]]) -> MediaItem? {
        guard let duration = seconds(item.runTimeTicks), let title = item.name else { return nil }
        return MediaItem(
            serverID: library.serverID,
            itemKey: item.id,
            externalID: movieID(item.providerIds),
            libraryID: library.id,
            kind: .movie,
            title: title,
            year: item.productionYear,
            duration: duration,
            summary: item.overview,
            contentRating: item.officialRating,
            audience: Audience.classify(rating: item.officialRating, age: nil),
            genres: item.genres ?? [],
            networks: [],
            collections: collections[item.id] ?? [],
            countries: countries(of: item),
            artwork: Artwork(
                poster: image(of: item, JellyfinAPI.ImageType.primary),
                backdrop: backdrop(of: item),
                logo: image(of: item, JellyfinAPI.ImageType.logo),
                thumbnail: image(of: item, JellyfinAPI.ImageType.primary)
            ),
            versions: versions(of: item),
            titleIDs: titleIDs(item.providerIds),
            addedAt: JellyfinCoding.date(item.dateCreated)
        )
    }

    static func episode(
        _ item: JellyfinItem,
        series: JellyfinItem?,
        networks: [String],
        library: MediaLibrary,
        collections: [String: [String]]
    ) -> MediaItem? {
        guard let duration = seconds(item.runTimeTicks), let seriesID = item.seriesId else { return nil }
        let title = item.name ?? item.seriesName ?? series?.name ?? ""
        let rating = item.officialRating ?? series?.officialRating
        let memberships = (collections[seriesID] ?? []) + (collections[item.id] ?? [])
        return MediaItem(
            serverID: library.serverID,
            itemKey: item.id,
            externalID: episodeID(item.providerIds),
            libraryID: library.id,
            kind: .episode,
            title: title,
            series: SeriesInfo(
                key: seriesID,
                title: item.seriesName ?? series?.name ?? title,
                seasonNumber: item.parentIndexNumber,
                episodeNumber: item.indexNumber,
                externalID: showID(series?.providerIds)
            ),
            year: item.productionYear ?? series?.productionYear,
            duration: duration,
            summary: item.overview,
            contentRating: rating,
            audience: Audience.classify(rating: rating, age: nil),
            genres: series?.genres ?? item.genres ?? [],
            networks: networks,
            collections: Array(Set(memberships)).sorted(),
            countries: countries(of: series ?? item),
            artwork: Artwork(
                poster: JellyfinImageReference(itemID: seriesID, type: JellyfinAPI.ImageType.primary, tag: item.seriesPrimaryImageTag)?.encoded
                    ?? series.flatMap { image(of: $0, JellyfinAPI.ImageType.primary) },
                backdrop: JellyfinImageReference(
                    itemID: item.parentBackdropItemId,
                    type: JellyfinAPI.ImageType.backdrop,
                    tag: item.parentBackdropImageTags?.first
                )?.encoded ?? series.flatMap(backdrop(of:)) ?? backdrop(of: item),
                logo: JellyfinImageReference(itemID: item.parentLogoItemId, type: JellyfinAPI.ImageType.logo, tag: item.parentLogoImageTag)?.encoded
                    ?? series.flatMap { image(of: $0, JellyfinAPI.ImageType.logo) },
                thumbnail: image(of: item, JellyfinAPI.ImageType.primary)
            ),
            versions: versions(of: item),
            titleIDs: titleIDs(series?.providerIds),
            addedAt: JellyfinCoding.date(item.dateCreated)
        )
    }

    // MARK: - Files

    /// Every copy of the item, in the server's order; ``MediaVersion/filePath``
    /// holds the copy's media source id, which stream URLs name.
    static func versions(of item: JellyfinItem) -> [MediaVersion] {
        (item.mediaSources ?? []).enumerated().map { index, source in
            let streams = source.mediaStreams ?? []
            let video = streams.first { $0.type == JellyfinAPI.StreamType.video }
            let audio = streams.first { $0.type == JellyfinAPI.StreamType.audio && $0.isDefault == true }
                ?? streams.first { $0.type == JellyfinAPI.StreamType.audio }
            return MediaVersion(
                index: index,
                container: source.container,
                videoCodec: video?.codec,
                audioCodec: audio?.codec,
                filePath: source.id,
                height: video?.height,
                bitrateKbps: source.bitrate.map { $0 / bitsPerKilobit }
            )
        }
    }

    private static let bitsPerKilobit = 1_000

    // MARK: - Identity

    /// Ids that name the same title on another server: an IMDb id is unique
    /// across movies, shows and episodes; TMDB and TVDB ids get their kind.
    static func movieID(_ ids: [String: String]?) -> String? {
        if let imdb = imdbID(ids) { return Scheme.imdb + imdb }
        return ids?[JellyfinAPI.Provider.tmdb].map { Scheme.tmdbMovie + $0 }
    }

    static func showID(_ ids: [String: String]?) -> String? {
        if let tvdb = ids?[JellyfinAPI.Provider.tvdb] { return Scheme.tvdb + tvdb }
        if let tmdb = ids?[JellyfinAPI.Provider.tmdb] { return Scheme.tmdbShow + tmdb }
        return imdbID(ids).map { Scheme.imdb + $0 }
    }

    static func episodeID(_ ids: [String: String]?) -> String? {
        if let imdb = imdbID(ids) { return Scheme.imdb + imdb }
        if let tvdb = ids?[JellyfinAPI.Provider.tvdb] { return Scheme.tvdbEpisode + tvdb }
        return ids?[JellyfinAPI.Provider.tmdb].map { Scheme.tmdbEpisode + $0 }
    }

    /// The title's public database ids, for ``TitleClassification``.
    static func titleIDs(_ ids: [String: String]?) -> TitleIDs? {
        guard let ids else { return nil }
        var guids: [String] = []
        if let imdb = imdbID(ids) { guids.append(Scheme.imdb + imdb) }
        if let tmdb = ids[JellyfinAPI.Provider.tmdb] { guids.append(Scheme.tmdb + tmdb) }
        if let tvdb = ids[JellyfinAPI.Provider.tvdb] { guids.append(Scheme.tvdb + tvdb) }
        return TitleIDs(guids: guids)
    }

    private static func imdbID(_ ids: [String: String]?) -> String? {
        ids?[JellyfinAPI.Provider.imdb].flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: - Helpers

    /// Production countries. Jellyfin's TV metadata has none, so a show
    /// originally in Japanese counts as Japanese, which is what anime
    /// detection needs (``AnimeDetector``) and what Plex's country says.
    private static func countries(of item: JellyfinItem) -> [String] {
        if let locations = item.productionLocations, !locations.isEmpty {
            return locations
        }
        return item.originalLanguage.flatMap { originCountries[$0.lowercased()] }.map { [$0] } ?? []
    }

    private static let originCountries = ["ja": "Japan"]

    private static func image(of item: JellyfinItem, _ type: String) -> String? {
        JellyfinImageReference(itemID: item.id, type: type, tag: item.imageTags?[type])?.encoded
    }

    private static func backdrop(of item: JellyfinItem) -> String? {
        JellyfinImageReference(itemID: item.id, type: JellyfinAPI.ImageType.backdrop, tag: item.backdropImageTags?.first)?.encoded
    }

    private static func seconds(_ ticks: Int64?) -> TimeInterval? {
        guard let ticks, ticks > .zero else { return nil }
        return TimeInterval(ticks) / JellyfinAPI.Defaults.ticksPerSecond
    }
}
