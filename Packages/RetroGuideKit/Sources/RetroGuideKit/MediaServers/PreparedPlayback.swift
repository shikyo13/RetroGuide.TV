import Foundation

/// A stream and the track list belonging to the version it will play.
public struct PreparedPlayback: Sendable {
    public let request: StreamRequest
    public let tracks: ItemTracks?
}

extension MediaServerClient {
    /// Fetches a known single copy's tracks alongside stream preparation.
    /// With multiple copies, waits for the server to choose the playable version.
    public func preparePlayback(
        for item: MediaItem,
        startingAt position: TimeInterval,
        capabilities: PlaybackCapabilities,
        preferences: LanguagePreferences?
    ) async throws -> PreparedPlayback {
        // Filtering short clips does not renumber the retained server versions.
        let singleVersion = item.versions.count == 1 ? item.versions.first?.index : nil
        async let singleCopyTracks = singleVersion != nil
            ? tracks(for: item, version: singleVersion, preferences: preferences) : nil
        let request = try await streamRequest(for: item, startingAt: position, capabilities: capabilities)
        let selectedTracks = singleVersion != nil && singleVersion == request.versionIndex
            ? await singleCopyTracks
            : await tracks(for: item, version: request.versionIndex, preferences: preferences)
        return PreparedPlayback(request: request, tracks: selectedTracks)
    }
}
