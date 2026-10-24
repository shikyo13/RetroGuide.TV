import Foundation
import Testing
@testable import RetroGuideKit

/// Plex and Jellyfin reading the same files: their native ids never match
/// (`plex://` guids vs Jellyfin's), so copies are found by public database
/// ids and, for episodes (Plex lists none for them), by episode number.
/// Items are shaped like the two mappers produce them.
@Suite("Plex and Jellyfin together")
struct PlexJellyfinMergeTests {
    private let plexShow = "plex://show/the-show"

    private func snapshot(_ server: String, _ items: [MediaItem]) -> LibrarySnapshot {
        LibrarySnapshot(
            serverID: server,
            serverName: server.capitalized,
            libraries: [MediaLibrary(serverID: server, key: "1", title: "Library", kind: .shows)],
            items: items
        )
    }

    private func movie(server: String, key: String, externalID: String, imdb: UInt32) -> MediaItem {
        let ids = TitleIDs(imdb: imdb)
        return MediaItem(
            serverID: server, itemKey: key, externalID: externalID, libraryID: "\(server)/1", kind: .movie, title: "Jurassic Park",
            year: 1993, duration: 7_620, titleIDs: ids, publicIDs: ids
        )
    }

    private func plexEpisode(_ number: Int, key: String? = nil, tvdb: UInt32? = nil) -> MediaItem {
        MediaItem(
            serverID: "plex", itemKey: key ?? "p\(number)", externalID: "plex://episode/\(number)", libraryID: "plex/1", kind: .episode,
            title: "Episode \(number)", series: SeriesInfo(key: "10", title: "The Show", seasonNumber: 1, episodeNumber: number, externalID: plexShow),
            duration: 1_320, titleIDs: TitleIDs(tvdb: 100), publicIDs: tvdb.map { TitleIDs(tvdb: $0) }
        )
    }

    private func jellyfinEpisode(_ number: Int, key: String? = nil, tvdb: UInt32? = nil, imdb: UInt32? = nil) -> MediaItem {
        MediaItem(
            serverID: "jellyfin", itemKey: key ?? "j\(number)", libraryID: "jellyfin/1", kind: .episode,
            title: "Episode \(number)", series: SeriesInfo(key: "abc", title: "The Show", seasonNumber: 1, episodeNumber: number, externalID: "tvdb://100"),
            duration: 1_320, titleIDs: TitleIDs(tvdb: 100), publicIDs: TitleIDs(imdb: imdb, tvdb: tvdb)
        )
    }

    @Test("A movie on both is kept once, from the first server")
    func movieOnBoth() {
        let index = LibraryIndex(snapshots: [
            snapshot("plex", [movie(server: "plex", key: "1", externalID: "plex://movie/jp", imdb: 107_290)]),
            snapshot("jellyfin", [movie(server: "jellyfin", key: "a", externalID: "imdb://tt0107290", imdb: 107_290)]),
        ])
        #expect(index.items.map(\.id) == ["plex/1"])
    }

    @Test("A show on both is one show, with the episodes only Jellyfin has")
    func showOnBoth() {
        let index = LibraryIndex(snapshots: [
            snapshot("plex", [1, 2].map { plexEpisode($0) }),
            snapshot("jellyfin", [1, 2, 3].map { jellyfinEpisode($0) }),
        ])
        #expect(index.items.compactMap(\.series?.episodeNumber).sorted() == [1, 2, 3])
        #expect(Set(index.items.map(\.showID)) == [plexShow])
        #expect(index.items.filter { $0.series?.episodeNumber != 3 }.allSatisfy { $0.serverID == "plex" })
    }

    @Test("Adding Jellyfin never folds two Plex episodes into one, however it numbers them")
    func numberingDisagreement() {
        // Jellyfin numbers Plex's episode 2 as episode 1 (another database's order).
        let plex = [plexEpisode(1, tvdb: 11), plexEpisode(2, tvdb: 12)]
        let index = LibraryIndex(snapshots: [
            snapshot("plex", plex),
            snapshot("jellyfin", [jellyfinEpisode(1, tvdb: 12)]),
        ])
        #expect(index.items.map(\.id).sorted() == plex.map(\.id).sorted())
    }

    @Test("Episodes a server gives the same public id stay apart")
    func repeatedPublicID() {
        // Bad metadata: every episode carries the show's IMDb id.
        let index = LibraryIndex(snapshots: [
            snapshot("jellyfin", [1, 2, 3].map { jellyfinEpisode($0, imdb: 115_082) }),
        ])
        #expect(index.items.count == 3)
    }
}
