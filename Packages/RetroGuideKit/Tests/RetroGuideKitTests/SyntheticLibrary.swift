import Foundation
@testable import RetroGuideKit

/// Deterministic, realistic-looking libraries for lineup benchmarks: long-tailed
/// episode counts, Plex-style genre tags (some missing or odd), anime that is
/// sometimes tagged "Anime" and sometimes only Japanese animation, and movies
/// spread over decades.
struct SyntheticLibrary {
    struct Profile: Sendable, CustomStringConvertible {
        let name: String
        var shows = 0
        var movies = 0
        /// Share of shows that are anime.
        var animeShare = 0.2
        /// Share of titles with no genres at all.
        var untaggedShare = 0.03
        var serverID = "bench"

        var description: String { name }

        static let tiny = Profile(name: "tiny", shows: 3, movies: 10)
        static let small = Profile(name: "small", shows: 20, movies: 40)
        static let medium = Profile(name: "medium", shows: 130, movies: 265, animeShare: 0.38)
        static let large = Profile(name: "large", shows: 1_000, movies: 10_000)
        static let huge = Profile(name: "huge", shows: 5_000, movies: 50_000)
        static let allAnime = Profile(name: "all anime", shows: 150, movies: 30, animeShare: 1)
        static let moviesOnly = Profile(name: "movies only", shows: 0, movies: 600)
        static let showsOnly = Profile(name: "shows only", shows: 200, movies: 0)
        static let messy = Profile(name: "messy metadata", shows: 150, movies: 300, untaggedShare: 0.4)

        static let all: [Profile] = [.tiny, .small, .medium, .large, .allAnime, .moviesOnly, .showsOnly, .messy]
    }

    private static let showGenres = [
        ["Comedy"], ["Comedy", "Family"], ["Drama"], ["Crime", "Drama"], ["Crime", "Mystery"],
        ["Sci-Fi & Fantasy"], ["Science Fiction", "Drama"], ["Documentary"], ["Documentary", "History"],
        ["Reality"], ["Game Show"], ["Talk"], ["Animation", "Comedy"], ["Kids", "Animation"],
        ["Action", "Adventure"], ["Horror", "Thriller"], ["Western"], ["Romance", "Drama"], ["Food", "Reality"],
    ]
    private static let animeGenres = [
        ["Anime", "Action", "Adventure", "Animation"], ["Animation", "Action", "Fantasy"], ["Anime", "Comedy", "Romance"],
        ["Animation", "Drama", "Sci-Fi & Fantasy"], ["Anime", "Mystery", "Thriller"],
    ]
    private static let movieGenres = [
        ["Action"], ["Action", "Thriller"], ["Comedy"], ["Comedy", "Romance"], ["Drama"], ["Horror"], ["Science Fiction"],
        ["Animation", "Family"], ["Documentary"], ["Music"], ["War", "History"], ["Western"], ["Fantasy", "Adventure"],
        ["Crime", "Thriller"], ["Mystery"],
    ]
    private static let networks = ["ABC", "NBC", "CBS", "FOX", "HBO", "Netflix", "BBC One", "TV Tokyo", "Fuji TV", "AMC", "Discovery"]

    static func items(_ profile: Profile) -> [MediaItem] {
        var generator = SeededGenerator(seed: StableHash.fnv1a(profile.name))
        var result: [MediaItem] = []
        for show in 0..<profile.shows {
            let isAnime = Double.random(in: 0..<1, using: &generator) < profile.animeShare
            let untagged = Double.random(in: 0..<1, using: &generator) < profile.untaggedShare
            let genres = untagged ? [] : (isAnime ? animeGenres : showGenres).randomElement(using: &generator) ?? []
            // Long tail: most shows 10–60 episodes, a few hundreds.
            let roll = Double.random(in: 0..<1, using: &generator)
            let episodes = roll < 0.05 ? Int.random(in: 200...900, using: &generator) : (roll < 0.25 ? Int.random(in: 60...200, using: &generator) : Int.random(in: 1...60, using: &generator))
            let length: TimeInterval = isAnime ? 24 * 60 : (Bool.random(using: &generator) ? 22 * 60 : 44 * 60)
            let year = Int.random(in: 1960...2025, using: &generator)
            let network = networks.randomElement(using: &generator) ?? ""
            for episode in 0..<episodes {
                let season = episode / 24 + 1
                result.append(MediaItem(
                    serverID: profile.serverID,
                    itemKey: "s\(show)e\(episode)",
                    externalID: "plex://episode/\(profile.name)-\(show)-\(episode)",
                    libraryID: "\(profile.serverID)/\(isAnime ? "anime" : "tv")",
                    kind: .episode,
                    title: "Episode \(episode + 1)",
                    series: SeriesInfo(key: "show\(show)", title: "Show \(show)", seasonNumber: season, episodeNumber: episode % 24 + 1),
                    year: year + season - 1,
                    duration: length,
                    genres: genres,
                    networks: [network],
                    countries: isAnime ? ["Japan"] : ["United States of America"]
                ))
            }
        }
        for movie in 0..<profile.movies {
            let untagged = Double.random(in: 0..<1, using: &generator) < profile.untaggedShare
            result.append(MediaItem(
                serverID: profile.serverID,
                itemKey: "m\(movie)",
                externalID: "plex://movie/\(profile.name)-\(movie)",
                libraryID: "\(profile.serverID)/movies",
                kind: .movie,
                title: "Movie \(movie)",
                year: Int.random(in: 1950...2025, using: &generator),
                duration: TimeInterval(Int.random(in: 80...160, using: &generator) * 60),
                genres: untagged ? [] : movieGenres.randomElement(using: &generator) ?? []
            ))
        }
        return result
    }
}
