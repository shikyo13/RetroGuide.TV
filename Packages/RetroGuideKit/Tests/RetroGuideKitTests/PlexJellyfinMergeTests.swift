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

    // MARK: - Server order

    /// The same show as each server describes it: Plex and Jellyfin name its
    /// network and the show differently and tag different genres.
    private func describedEpisode(_ server: String, _ number: Int) -> MediaItem {
        let isPlex = server == "plex"
        return MediaItem(
            serverID: server, itemKey: "\(server)\(number)", externalID: isPlex ? "plex://episode/\(number)" : nil, libraryID: "\(server)/1",
            kind: .episode, title: "Episode \(number)",
            series: SeriesInfo(key: isPlex ? "10" : "abc", title: isPlex ? "Bizarre Foods" : "Bizarre Foods with Andrew Zimmern",
                               seasonNumber: 1, episodeNumber: number, externalID: isPlex ? plexShow : "tvdb://100"),
            duration: 1_320, genres: isPlex ? ["Reality", "Food"] : ["Documentary"], networks: isPlex ? ["Travel Channel"] : ["TRAVEL CHANNEL"],
            titleIDs: TitleIDs(tvdb: 100)
        )
    }

    private func description(_ index: LibraryIndex) -> Set<String> {
        Set(index.items.map { "\($0.headline)|\($0.genres)|\($0.networks)|\($0.series?.episodeNumber ?? 0)" })
    }

    @Test("Which server is listed first decides only which copy plays, not what a show is")
    func orderIndependent() {
        let plex = snapshot("plex", [1, 2].map { describedEpisode("plex", $0) })
        let jellyfin = snapshot("jellyfin", [1, 2, 3].map { describedEpisode("jellyfin", $0) })
        let plexFirst = LibraryIndex(snapshots: [plex, jellyfin])
        let jellyfinFirst = LibraryIndex(snapshots: [jellyfin, plex])
        #expect(description(plexFirst) == description(jellyfinFirst))
        #expect(plexFirst.facets.networks.map(\.name) == jellyfinFirst.facets.networks.map(\.name))
        #expect(jellyfinFirst.items.filter { $0.series?.episodeNumber == 1 }.map(\.serverID) == ["jellyfin"])
    }

    @Test("Adding Jellyfin keeps the names Plex gave a show and its network")
    func addingKeepsNames() {
        let plexAlone = LibraryIndex(snapshots: [snapshot("plex", [1, 2].map { describedEpisode("plex", $0) })])
        let both = LibraryIndex(snapshots: [
            snapshot("jellyfin", [1, 2, 3].map { describedEpisode("jellyfin", $0) }),
            snapshot("plex", [1, 2].map { describedEpisode("plex", $0) }),
        ])
        #expect(Set(both.facets.series.map(\.name)) == Set(plexAlone.facets.series.map(\.name)))
        #expect(both.facets.networks.map(\.name) == plexAlone.facets.networks.map(\.name))
    }

    @Test("A copy too short to air never plays over one that can")
    func shortCopyLoses() {
        var clip = movie(server: "plex", key: "1", externalID: "plex://movie/jp", imdb: 107_290)
        clip = MediaItem(
            serverID: clip.serverID, itemKey: clip.itemKey, externalID: clip.externalID, libraryID: clip.libraryID, kind: .movie,
            title: clip.title, year: clip.year, duration: 71, titleIDs: clip.titleIDs, publicIDs: clip.publicIDs
        )
        let index = LibraryIndex(snapshots: [
            snapshot("plex", [clip]),
            snapshot("jellyfin", [movie(server: "jellyfin", key: "a", externalID: "imdb://tt0107290", imdb: 107_290)]),
        ])
        #expect(index.items.map(\.id) == ["jellyfin/a"])
    }

    // MARK: - Libraries

    private func library(_ server: String, _ title: String) -> MediaLibrary {
        MediaLibrary(serverID: server, key: "1", title: title, kind: .shows)
    }

    @Test("The same library on Plex and Jellyfin is one library, with the episodes only Jellyfin has")
    func twinLibraries() throws {
        let index = LibraryIndex(snapshots: [
            LibrarySnapshot(serverID: "plex", serverName: "Komputer", libraries: [library("plex", "TV Shows")], items: [1, 2].map { plexEpisode($0) }),
            LibrarySnapshot(serverID: "jellyfin", serverName: "Komputer", libraries: [library("jellyfin", "TV Shows")], items: [1, 2, 3].map { jellyfinEpisode($0) }),
        ])
        let libraries = index.facets.libraries
        #expect(libraries.map(\.name) == ["TV Shows"])
        let id = try #require(libraries.first?.id)
        #expect(ChannelRule(libraryIDs: [id]).matchingItems(in: index).count == 3)
    }

    @Test("Same-named libraries holding different titles stay apart")
    func differentLibraries() {
        let index = LibraryIndex(snapshots: [
            LibrarySnapshot(serverID: "plex", serverName: "Home", libraries: [library("plex", "TV Shows")], items: [1, 2].map { plexEpisode($0, key: "p\($0)") }),
            LibrarySnapshot(serverID: "jellyfin", serverName: "Friend", libraries: [library("jellyfin", "TV Shows")], items: [5, 6].map { number in
                MediaItem(
                    serverID: "jellyfin", itemKey: "o\(number)", libraryID: "jellyfin/1", kind: .episode, title: "Other \(number)",
                    series: SeriesInfo(key: "zzz", title: "Other Show", seasonNumber: 1, episodeNumber: number, externalID: "tvdb://999"),
                    duration: 1_320, titleIDs: TitleIDs(tvdb: 999)
                )
            }),
        ])
        #expect(index.facets.libraries.map(\.name).sorted() == ["TV Shows · Friend", "TV Shows · Home"])
    }
}
