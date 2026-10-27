import Foundation
import Testing
@testable import RetroGuideKit

@Suite("Parental selections across servers")
struct ParentalMultiServerTests {
    func movie(_ server: String, key: String = "film", imdb: UInt32? = 10, tmdb: UInt32? = 20, title: String = "Same Name", year: Int = 1982, rating: String? = "PG", library: String = "movies", collections: [String] = []) -> MediaItem {
        MediaItem(serverID: server, itemKey: key, libraryID: server + "/" + library, kind: .movie,
            title: title, year: year, duration: 3600, contentRating: rating, collections: collections,
            publicIDs: TitleIDs(imdb: imdb, tmdb: tmdb))
    }
    func episode(_ server: String, key: String, show: String = "series", tvdb: UInt32 = 30, rating: String = "TV-G") -> MediaItem {
        MediaItem(serverID: server, itemKey: key, libraryID: server + "/tv", kind: .episode, title: key,
            series: SeriesInfo(key: show, title: "A Show", seasonNumber: 1, episodeNumber: 1), duration: 1800,
            contentRating: rating, titleIDs: TitleIDs(tvdb: tvdb))
    }
    func snapshots(_ items: [MediaItem]) -> [LibrarySnapshot] {
        Dictionary(grouping: items, by: \.serverID).sorted { $0.key < $1.key }.map { server, items in
            LibrarySnapshot(serverID: server, serverName: server, libraries: [], items: items)
        }
    }
    var policy: ParentalPolicy { var value = ParentalPolicy(); value.isEnabled = true; return value }
    func ids(_ value: ParentalPolicy, _ items: [MediaItem]) -> Set<String> {
        Set(value.filtering(snapshots(items)).flatMap { $0.items.map(\.id) })
    }

    @Test("A title has one choice across servers, libraries and duplicate files")
    func singleChoice() {
        let a = movie("plex"), b = movie("jellyfin"), c = movie("plex", key: "second-copy", library: "family")
        let catalog = ParentalTitleCatalog(snapshots: snapshots([a,b,c]))
        #expect(catalog.titles.count == 1)
        #expect(catalog.titles[0].identity.sourceIDs == [a.id,b.id,c.id])
        var value = policy
        value.blockedTitles = catalog.identities(for: [catalog.titles[0].id])
        #expect(ids(value, [a,b,c]).isEmpty)
    }

    @Test("IDs bridge server formats and persist after original servers disappear")
    func bridgeAndRemoval() throws {
        let a = movie("plex", tmdb: nil), b = movie("jellyfin"), c = movie("third", imdb: nil)
        let all = snapshots([a,b,c])
        var value = policy
        value.selectedContentOnly = true
        value.allowedTitles = [ParentalTitleIdentity(item: a)]
        #expect(ids(value, [a,b,c]) == [a.id,b.id,c.id])
        value = value.resolvingTitles(in: ParentalTitleCatalog(snapshots: all))
        let saved = try JSONDecoder().decode(ParentalPolicy.self, from: JSONEncoder().encode(value))
        #expect(ids(saved, [c]) == [c.id])
        #expect(saved.filtering(all).flatMap(\.items).count == saved.filtering(all.reversed()).flatMap(\.items).count)
        value.allowedTitles = []
        value.blockedTitles = saved.allowedTitles
        value.selectedContentOnly = false
        #expect(ids(value, [c]).isEmpty)
    }

    @Test("Remakes, unmatched names and conflicting IDs cannot inherit approval")
    func distinctTitles() {
        let original = movie("plex")
        let remake = movie("jellyfin", imdb: 11, tmdb: 21, year: 2011)
        let unknown = movie("third", imdb: nil, tmdb: nil)
        let conflicting = movie("fourth", imdb: 10, tmdb: 999)
        var value = policy
        value.selectedContentOnly = true
        value.allowedTitles = [ParentalTitleIdentity(item: original)]
        #expect(ParentalTitleCatalog(snapshots: snapshots([original,remake,unknown,conflicting])).titles.count == 4)
        #expect(ids(value, [original,remake,unknown,conflicting]) == [original.id])
        value.blockedTitles = value.allowedTitles
        #expect(ids(value, [original,remake,unknown,conflicting]).isEmpty)
    }

    @Test("Show selections cover future episodes but cannot override ratings or libraries")
    func showAndLimits() throws {
        let a = episode("plex", key: "one"), b = episode("jellyfin", key: "two"), future = episode("third", key: "future")
        let adult = episode("jellyfin", key: "adult", rating: "TV-MA")
        var value = policy
        value.selectedContentOnly = true
        value.allowedTitles = [ParentalTitleIdentity(item: a)]
        #expect(ids(value, [a,b,future,adult]) == [a.id,b.id,future.id])
        value.allLibraries = false
        value.libraryIDs = ["jellyfin/tv"]
        #expect(ids(value, [a,b,future,adult]) == [b.id])
        value.blockedTitles = [ParentalTitleIdentity(item: future)]
        #expect(ids(value, [a,b,future,adult]).isEmpty)
    }

    @Test("Movie and show database namespaces stay separate")
    func namespaces() {
        let film = movie("plex", imdb: nil, tmdb: 30)
        let show = MediaItem(serverID: "plex", itemKey: "episode", libraryID: "plex/tv", kind: .episode, title: "Episode",
            series: SeriesInfo(key: "show", title: "A Show", seasonNumber: 1, episodeNumber: 1), duration: 1800,
            contentRating: "TV-G", titleIDs: TitleIDs(tmdb: 30))
        var value = policy
        value.blockedTitles = [ParentalTitleIdentity(item: film)]
        #expect(ids(value, [film,show]) == [show.id])
    }

    @Test("Collections include matching copies but explicit blocks and limits win")
    func collections() {
        let a = movie("plex", collections: ["Family Favorites"]), b = movie("jellyfin")
        let adult = movie("third", rating: "R")
        var value = policy
        value.selectedContentOnly = true
        value.collectionNames = ["family favorites"]
        #expect(ids(value, [a,b,adult]) == [a.id,b.id])
        value.blockedTitles = [ParentalTitleIdentity(item: b)]
        #expect(ids(value, [a,b,adult]).isEmpty)
        value.blockedTitles = []
        value.allLibraries = false
        value.libraryIDs = [b.libraryID]
        #expect(ids(value, [a,b,adult]).isEmpty)
    }

    @Test("Existing source-specific choices migrate without losing blocked titles")
    func legacyMigration() throws {
        let a = movie("plex"), b = movie("jellyfin")
        var value = policy
        value.blockedTitleIDs = [a.id]
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String:Any])
        json.removeValue(forKey: "allowedTitles")
        json.removeValue(forKey: "blockedTitles")
        let legacy = try JSONDecoder().decode(ParentalPolicy.self, from: JSONSerialization.data(withJSONObject: json))
        let migrated = legacy.resolvingTitles(in: ParentalTitleCatalog(snapshots: snapshots([a,b])))
        #expect(migrated.blockedTitleIDs.isEmpty)
        #expect(migrated.blockedTitles.count == 1)
        #expect(ids(migrated, [b]).isEmpty)
    }
}
