#if DEBUG
import Foundation
import RetroGuideKit

/// A self-contained media library for screenshots and demos, read from a JSON
/// file: titles, artwork paths and a streamable URL per title. Development only.
struct DemoCatalog: Decodable, Sendable {
    struct Server: Decodable, Sendable {
        let id: String
        let name: String
    }

    struct Library: Decodable, Sendable {
        let key: String
        let title: String
        let kind: MediaLibrary.Kind
    }

    struct Series: Decodable, Sendable {
        let key: String
        let title: String
        let season: Int
        let episode: Int
    }

    struct Art: Decodable, Sendable {
        let poster: String?
        let backdrop: String?
        let logo: String?
        let thumbnail: String?
    }

    struct Item: Decodable, Sendable {
        let itemKey: String
        let library: String
        let kind: MediaKind
        let title: String
        let series: Series?
        let year: Int?
        let duration: TimeInterval
        let summary: String?
        let contentRating: String?
        let genres: [String]
        let networks: [String]
        let collections: [String]
        let artwork: Art
        let stream: URL
    }

    let server: Server
    let libraries: [Library]
    let items: [Item]

    static func load(from url: URL) -> DemoCatalog? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DemoCatalog.self, from: data)
    }

    func mediaLibraries() -> [MediaLibrary] {
        libraries.map { MediaLibrary(serverID: server.id, key: $0.key, title: $0.title, kind: $0.kind) }
    }

    func mediaItems(in libraries: [MediaLibrary]) -> [MediaItem] {
        let keys = Set(libraries.map(\.key))
        return items.filter { keys.contains($0.library) }.map(mediaItem)
    }

    func stream(forItemKey key: String) -> URL? {
        items.first { $0.itemKey == key }?.stream
    }

    private func mediaItem(_ item: Item) -> MediaItem {
        MediaItem(
            serverID: server.id,
            itemKey: item.itemKey,
            libraryID: MediaLibrary(serverID: server.id, key: item.library, title: "", kind: .unsupported).id,
            kind: item.kind,
            title: item.title,
            series: item.series.map {
                SeriesInfo(key: $0.key, title: $0.title, seasonNumber: $0.season, episodeNumber: $0.episode)
            },
            year: item.year,
            duration: item.duration,
            summary: item.summary,
            contentRating: item.contentRating,
            audience: Audience.classify(rating: item.contentRating),
            genres: item.genres,
            networks: item.networks,
            collections: item.collections,
            artwork: Artwork(
                poster: item.artwork.poster,
                backdrop: item.artwork.backdrop,
                logo: item.artwork.logo,
                thumbnail: item.artwork.thumbnail
            ),
            versions: [MediaVersion(container: nil, videoCodec: nil, audioCodec: nil, filePath: item.stream.absoluteString)]
        )
    }
}
#endif
