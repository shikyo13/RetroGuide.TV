import Foundation
import Testing
@testable import RetroGuideKit

@Suite("Parental content restrictions")
struct ParentalPolicyTests {
    func item(_ key: String = "item", server: String = "plex", library: String = "family", rating: String? = "PG", kind: MediaKind = .movie, collections: [String] = []) -> MediaItem {
        MediaItem(serverID: server, itemKey: key, libraryID: library, kind: kind, title: key,
            duration: 3600, contentRating: rating, collections: collections,
            publicIDs: TitleIDs(imdb: 42))
    }
    var policy: ParentalPolicy { var value = ParentalPolicy(); value.isEnabled = true; return value }

    @Test("Rating limits use the original certificate, not coarse audience buckets", arguments: ["plex", "jellyfin"])
    func preciseRatings(server: String) {
        var value = policy
        value.maximumMovieRating = .g
        #expect(value.allows(item(server: server, rating: "G")))
        #expect(!value.allows(item(server: server, rating: "PG")))
        value.maximumMovieRating = .pg
        #expect(value.allows(item(server: server, rating: " us/pg ")))
        #expect(!value.allows(item(server: server, rating: "PG-13")))
        #expect(!value.allows(item(server: server, rating: "R")))
        #expect(value.allows(item(server: server, rating: "TV-Y7-FV", kind: .episode)))
        #expect(!value.allows(item(server: server, rating: "TV-14", kind: .episode)))
    }

    @Test("Missing, foreign and unknown ratings fail closed")
    func unknownRatings() {
        for rating: String? in [nil, "", "NR", "GB/15", "DE/6", "made up", "TV-PG"] {
            #expect(policy.exclusion(for: item(rating: rating)) == .unrated)
        }
        var value = policy
        value.allowsUnrated = true
        #expect(value.allows(item(rating: nil)))
        #expect(!value.allows(item(rating: "R")))
    }

    @Test("Selections stay inside rating and library limits, with explicit blocks winning")
    func intersections() {
        var value = policy
        value.allLibraries = false
        value.libraryIDs = ["family"]
        value.selectedContentOnly = true
        #expect(!value.allows(item()))
        value.collectionNames = ["Learning"]
        #expect(value.allows(item(collections: ["Learning"])))
        #expect(!value.allows(item(library: "adults", collections: ["Learning"])))
        #expect(!value.allows(item(rating: "R", collections: ["Learning"])))
        value.titleIDs = ["plex/item"]
        #expect(value.allows(item()))
        value.blockedTitleIDs = ["plex/item"]
        #expect(!value.allows(item(collections: ["Learning"])))
    }

    @Test("Unselected libraries cannot authorize a duplicate on another server")
    func filterBeforeMerge() {
        var value = policy
        value.allLibraries = false
        value.libraryIDs = ["family"]
        let restricted = item(server: "plex", library: "adults", rating: "R")
        let allowed = item(server: "jellyfin", library: "family", rating: "G")
        let snapshots = [LibrarySnapshot(serverID: "plex", serverName: "Plex", libraries: [], items: [restricted]),
                         LibrarySnapshot(serverID: "jellyfin", serverName: "Jellyfin", libraries: [], items: [allowed])]
        let filtered = value.filtering(snapshots)
        let index = LibraryIndex(snapshots: filtered)
        #expect(index.items.count == 1)
        #expect(index.items.first?.serverID == "jellyfin")
        #expect(index.items.first?.contentRating == "G")
        #expect(snapshots.first?.items.count == 1)
        #expect(snapshots.first?.items.first?.contentRating == "R")
    }

    @Test("No selected libraries means no access, not all libraries")
    func emptySelection() {
        var value = policy
        value.allLibraries = false
        #expect(!value.allows(item()))
        value.allLibraries = true
        value.selectedContentOnly = true
        #expect(!value.allows(item()))
    }

    @Test("Disabling restrictions restores eligibility without altering original metadata")
    func disabledAndRoundTrip() throws {
        var value = policy
        value.blockedTitleIDs = ["plex/item"]
        let restored = try JSONDecoder().decode(ParentalPolicy.self, from: JSONEncoder().encode(value))
        #expect(restored == value)
        #expect(!restored.allows(item()))
        value.isEnabled = false
        #expect(value.allows(item(rating: "R")))
    }
    @Test("Plex and Jellyfin wire ratings reach the same restriction decision")
    func providerMapping() throws {
        let library = MediaLibrary(serverID: "server", key: "movies", title: "Movies", kind: .movies)
        for rating in ["G", "PG", "PG-13", "R", "NR"] {
            let plex = try JSONDecoder().decode(PlexMetadata.self, from: JSONSerialization.data(withJSONObject: [
                "ratingKey": "movie", "title": "Movie", "duration": 3_600_000, "contentRating": rating
            ]))
            let jellyfin = try JellyfinCoding.decoder.decode(JellyfinItem.self, from: JSONSerialization.data(withJSONObject: [
                "Id": "movie", "Name": "Movie", "RunTimeTicks": 36_000_000_000, "OfficialRating": rating
            ]))
            let plexItem = try #require(PlexItemMapper.movie(plex, library: library, memberships: PlexTagMemberships()))
            let jellyfinItem = try #require(JellyfinItemMapper.movie(jellyfin, library: library, collections: [:]))
            #expect(policy.allows(plexItem) == policy.allows(jellyfinItem))
            #expect(policy.allows(plexItem) == ["G", "PG"].contains(rating))
        }
    }

}
