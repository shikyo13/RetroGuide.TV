import Foundation
import Testing
@testable import RetroGuideKit

@Suite("Parental genre restrictions")
struct ParentalGenreTests {
    func item(server: String = "plex", genres: [String] = ["Animation", "Adventure"], rating: String? = "PG", library: String = "family") -> MediaItem {
        MediaItem(serverID: server, itemKey: "movie", libraryID: library, kind: .movie,
            title: "Movie", duration: 3600, contentRating: rating, genres: genres,
            collections: ["Learning"], publicIDs: TitleIDs(imdb: 42))
    }
    var policy: ParentalPolicy {
        var p = ParentalPolicy(); p.isEnabled = true; p.allGenres = false; p.genreNames = ["animation", "documentary"]; return p
    }
    @Test("Any exact normalized tag matches, without inferring educational or child suitability")
    func matching() {
        #expect(policy.allows(item()))
        #expect(policy.allows(item(genres: ["Drama", " DOCUMENTARY "])))
        #expect(!policy.allows(item(genres: [])))
        #expect(!policy.allows(item(genres: ["Comedy"])))
        var p = policy; p.genreNames = ["science"]
        #expect(!p.allows(item(genres: ["Science Fiction", "Sci-Fi & Fantasy"])))
        #expect(p.allows(item(genres: ["Science"])))
        p.genreNames = []
        #expect(!p.allows(item()))
        p.allGenres = true
        #expect(p.allows(item(genres: [])))
    }
    @Test("Genres intersect every other restriction")
    func intersections() {
        var p = policy
        #expect(!p.allows(item(rating: "R")))
        #expect(!p.allows(item(rating: nil)))
        p.allLibraries = false; p.libraryIDs = ["family"]
        #expect(!p.allows(item(library: "other")))
        p.selectedContentOnly = true
        #expect(!p.allows(item()))
        p.collectionNames = ["learning"]
        #expect(p.allows(item()))
        #expect(!p.allows(item(genres: ["Drama"])))
        p.blockedTitles = [ParentalTitleIdentity(item: item())]
        #expect(!p.allows(item()))
        p.isEnabled = false
        #expect(p.allows(item(genres: [], rating: "R", library: "other")))
    }
    @Test("Each original copy must pass, regardless of server order")
    func copies() {
        let snapshots = [
            LibrarySnapshot(serverID: "plex", serverName: "Same", libraries: [], items: [item(genres: ["Comedy"])]),
            LibrarySnapshot(serverID: "jellyfin", serverName: "Same", libraries: [], items: [item(server: "jellyfin")])
        ]
        for input in [snapshots, snapshots.reversed()] {
            let filtered = policy.filtering(input)
            #expect(filtered.flatMap(\.items).map(\.serverID) == ["jellyfin"])
            #expect(LibraryIndex(snapshots: filtered).items.count == 1)
            var p = policy; p.allLibraries = false; p.libraryIDs = ["excluded"]
            #expect(p.filtering(input).flatMap(\.items).isEmpty)
            p.allLibraries = true; p.blockedTitles = [ParentalTitleIdentity(item: item())]
            #expect(p.filtering(input).flatMap(\.items).isEmpty)
        }
        #expect(snapshots.flatMap(\.items).count == 2)
    }
    @Test("Both provider mappings retain multiple tags for restriction decisions")
    func providers() throws {
        let library = MediaLibrary(serverID: "server", key: "movies", title: "Movies", kind: .movies)
        let plex = try JSONDecoder().decode(PlexMetadata.self, from: JSONSerialization.data(withJSONObject: [
            "ratingKey": "movie", "title": "Movie", "duration": 3_600_000, "contentRating": "PG",
            "Genre": [["tag": "Adventure"], ["tag": "Animation"]]
        ]))
        let jellyfin = try JellyfinCoding.decoder.decode(JellyfinItem.self, from: JSONSerialization.data(withJSONObject: [
            "Id": "movie", "Name": "Movie", "RunTimeTicks": 36_000_000_000, "OfficialRating": "PG",
            "Genres": ["Adventure", "Animation"]
        ]))
        let items = [try #require(PlexItemMapper.movie(plex, library: library, memberships: PlexTagMemberships())),
                     try #require(JellyfinItemMapper.movie(jellyfin, library: library, collections: [:]))]
        for item in items {
            #expect(Set(item.genres) == ["Adventure", "Animation"])
            #expect(policy.allows(item))
            var p = policy; p.genreNames = ["documentary"]
            #expect(!p.allows(item))
        }
    }
    @Test("Old saved policies retain unrestricted genres and new choices persist")
    func persistence() throws {
        let data = try JSONEncoder().encode(policy)
        #expect(try JSONDecoder().decode(ParentalPolicy.self, from: data) == policy)
        var old = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        old.removeValue(forKey: "allGenres"); old.removeValue(forKey: "genreNames")
        let restored = try JSONDecoder().decode(ParentalPolicy.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(restored.allGenres); #expect(restored.genreNames.isEmpty)
        #expect(restored.allows(item(genres: [])))
    }
}
