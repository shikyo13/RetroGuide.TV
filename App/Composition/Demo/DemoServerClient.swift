#if DEBUG
import Foundation
import RetroGuideKit

/// Serves a ``DemoCatalog`` as if it were a media server: artwork comes from
/// local files and each title streams straight from its URL. Development only.
struct DemoServerClient: MediaServerClient {
    let serverID: String
    private let catalog: DemoCatalog

    init(catalog: DemoCatalog) {
        self.serverID = catalog.server.id
        self.catalog = catalog
    }

    func isReachable() async -> Bool {
        true
    }

    func fetchLibraries() async throws -> [MediaLibrary] {
        catalog.mediaLibraries()
    }

    func fetchItems(
        in libraries: [MediaLibrary],
        progress: @escaping @Sendable (LibraryLoadProgress) -> Void
    ) async throws -> [MediaItem] {
        progress(LibraryLoadProgress(fraction: 1, message: catalog.server.name))
        return catalog.mediaItems(in: libraries)
    }

    func streamRequest(
        for item: MediaItem,
        startingAt position: TimeInterval,
        capabilities: PlaybackCapabilities
    ) async throws -> StreamRequest {
        guard let url = catalog.stream(forItemKey: item.itemKey) else {
            throw StreamError.noPlayableVersion
        }
        return StreamRequest(
            url: url,
            startPosition: position,
            startsAtPosition: false,
            sessionID: UUID().uuidString,
            method: .directPlay
        )
    }

    func trackSelection(for item: MediaItem, preferences: LanguagePreferences?) async -> TrackSelection? {
        nil
    }

    func endStream(sessionID: String) async {}

    func imageURL(for reference: String, size: ImageSize) -> URL? {
        URL(fileURLWithPath: reference)
    }
}
#endif
