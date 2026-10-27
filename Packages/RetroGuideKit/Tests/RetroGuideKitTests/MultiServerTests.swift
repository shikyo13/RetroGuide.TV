import Foundation
import Testing
@testable import RetroGuideKit

@Suite("Multiple servers")
struct MultiServerTests {
    private func item(server: String, key: String, externalID: String?) -> MediaItem {
        MediaItem(serverID: server, itemKey: key, externalID: externalID, libraryID: "\(server)/1", kind: .movie, title: "Movie \(key)", duration: 5_400)
    }

    private func snapshot(_ server: String, _ items: [MediaItem], libraryTitle: String = "Movies") -> LibrarySnapshot {
        LibrarySnapshot(
            serverID: server,
            serverName: server.capitalized,
            libraries: [MediaLibrary(serverID: server, key: "1", title: libraryTitle, kind: .movies)],
            items: items
        )
    }

    @Test("The same title on two servers is kept once, from the first server")
    func deduplicates() {
        let index = LibraryIndex(snapshots: [
            snapshot("home", [item(server: "home", key: "1", externalID: "plex://movie/a")]),
            snapshot("friend", [
                item(server: "friend", key: "9", externalID: "plex://movie/a"),
                item(server: "friend", key: "10", externalID: "plex://movie/b"),
            ]),
        ])
        #expect(index.items.map(\.id).sorted() == ["friend/10", "home/1"])
    }

    @Test("Items without a global id are never merged")
    func keepsLocalOnlyItems() {
        let index = LibraryIndex(snapshots: [
            snapshot("home", [item(server: "home", key: "1", externalID: nil)]),
            snapshot("friend", [item(server: "friend", key: "1", externalID: nil)]),
        ])
        #expect(index.items.count == 2)
    }

    private func episode(server: String, key: String, show: String, showGuid: String?, number: Int, guid: String? = nil) -> MediaItem {
        MediaItem(
            serverID: server, itemKey: key, externalID: guid, libraryID: "\(server)/1", kind: .episode, title: "Episode \(number)",
            series: SeriesInfo(key: show, title: "The Show", seasonNumber: 1, episodeNumber: number, externalID: showGuid),
            duration: 1_320, genres: ["Comedy"]
        )
    }

    @Test("A show split across servers is one show with every episode once")
    func splitShow() throws {
        let guid = "plex://show/the-show"
        let index = LibraryIndex(snapshots: [
            snapshot("home", [1, 2, 3].map { episode(server: "home", key: "h\($0)", show: "10", showGuid: guid, number: $0) }),
            snapshot("friend", [2, 3, 4, 5].map { episode(server: "friend", key: "f\($0)", show: "77", showGuid: guid, number: $0) }),
        ])
        #expect(index.items.compactMap(\.series?.episodeNumber).sorted() == [1, 2, 3, 4, 5])
        #expect(Set(index.items.map(\.showID)) == [guid])
        #expect(index.facets.series.map(\.id) == [guid])
        #expect(index.items.filter { $0.series?.episodeNumber == 2 }.map(\.serverID) == ["home"])
    }

    @Test("A rule saved with one server's show id still matches that show")
    func legacyShowRule() {
        let guid = "plex://show/the-show"
        let index = LibraryIndex(snapshots: [
            snapshot("home", [episode(server: "home", key: "h1", show: "10", showGuid: guid, number: 1)]),
            snapshot("friend", [episode(server: "friend", key: "f2", show: "77", showGuid: guid, number: 2)]),
        ])
        // Either server's id names the whole show.
        #expect(ChannelRule(seriesIDs: ["home/10"]).matchingItems(in: index).count == 2)
        #expect(ChannelRule(seriesIDs: [guid]).matchingItems(in: index).count == 2)
    }

    @Test("Same-named libraries get the server name")
    func libraryNames() {
        let index = LibraryIndex(snapshots: [
            snapshot("home", [item(server: "home", key: "1", externalID: nil)]),
            snapshot("friend", [item(server: "friend", key: "2", externalID: nil)]),
        ])
        #expect(Set(index.facets.libraries.map(\.name)) == ["Movies · Home", "Movies · Friend"])
    }
}

@Suite("Merged copies keep their memberships")
struct MergedMembershipTests {
    @Test("An episode in two libraries counts for both, and for a collection only one copy is in")
    func keepsMembership() {
        let shared = "plex://episode/1"
        func copy(_ server: String, collections: [String]) -> MediaItem {
            MediaItem(serverID: server, itemKey: "1", externalID: shared, libraryID: "\(server)/1", kind: .episode, title: "E1",
                      series: SeriesInfo(key: "10", title: "Show", seasonNumber: 1, episodeNumber: 1), duration: 1_320, collections: collections)
        }
        func snapshot(_ server: String, _ item: MediaItem) -> LibrarySnapshot {
            LibrarySnapshot(serverID: server, serverName: server, libraries: [MediaLibrary(serverID: server, key: "1", title: "TV \(server)", kind: .shows)], items: [item])
        }
        let index = LibraryIndex(snapshots: [snapshot("a", copy("a", collections: [])), snapshot("b", copy("b", collections: ["Favorites"]))])
        #expect(index.items.count == 1)
        #expect(ChannelRule(libraryIDs: ["b/1"]).matchingItems(in: index).count == 1)
        #expect(ChannelRule(collections: ["Favorites"]).matchingItems(in: index).count == 1)
    }
}
