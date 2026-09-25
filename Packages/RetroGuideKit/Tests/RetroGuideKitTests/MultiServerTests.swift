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

    @Test("Same-named libraries get the server name")
    func libraryNames() {
        let index = LibraryIndex(snapshots: [
            snapshot("home", [item(server: "home", key: "1", externalID: nil)]),
            snapshot("friend", [item(server: "friend", key: "2", externalID: nil)]),
        ])
        #expect(Set(index.facets.libraries.map(\.name)) == ["Movies · Home", "Movies · Friend"])
    }
}
