import Foundation

/// Progress while downloading a library index.
public struct LibraryLoadProgress: Sendable, Hashable {
    public let fraction: Double
    public let message: String

    public init(fraction: Double, message: String) {
        self.fraction = min(max(fraction, .zero), 1)
        self.message = message
    }
}

/// Everything a player needs to start streaming an item mid-program.
public struct StreamRequest: Sendable, Hashable {
    public let url: URL
    /// Position the player should start at, in seconds from the start of the item.
    public let startPosition: TimeInterval
    /// Whether the stream itself already begins at `startPosition`
    /// (e.g. via an HLS `EXT-X-START` tag) so the player must not seek.
    public let startsAtPosition: Bool
    public let sessionID: String
    public let method: StreamMethod
    public let buffer: BufferProfile

    public init(
        url: URL,
        startPosition: TimeInterval,
        startsAtPosition: Bool,
        sessionID: String,
        method: StreamMethod,
        buffer: BufferProfile = .standard
    ) {
        self.url = url
        self.startPosition = startPosition
        self.startsAtPosition = startsAtPosition
        self.sessionID = sessionID
        self.method = method
        self.buffer = buffer
    }

    /// Whether the server holds resources for this stream that must be released.
    public var needsTeardown: Bool {
        method == .directStream
    }
}

/// The interface every media server backend implements.
///
/// Features only talk to this protocol, so adding a backend (Jellyfin, Emby)
/// means adding one conforming type and its sign-in flow.
public protocol MediaServerClient: Sendable {
    var serverID: String { get }

    /// A quick check that the server answers at its current address.
    func isReachable() async -> Bool

    func fetchLibraries() async throws -> [MediaLibrary]

    func fetchItems(
        in libraries: [MediaLibrary],
        progress: @escaping @Sendable (LibraryLoadProgress) -> Void
    ) async throws -> [MediaItem]

    /// Builds the cheapest stream the player can handle: the original file when
    /// possible, otherwise a server-side remux/transcode.
    func streamRequest(
        for item: MediaItem,
        startingAt position: TimeInterval,
        capabilities: PlaybackCapabilities
    ) async throws -> StreamRequest

    /// The item's audio and subtitle tracks, and the ones to play for this
    /// viewer: their choices for the item when they made any, otherwise picked
    /// with their account's `preferences`. `nil` when unknown (the player then
    /// falls back to its own language rules).
    func tracks(for item: MediaItem, preferences: LanguagePreferences?) async -> ItemTracks?

    /// Saves the tracks `choose` picks for `item` (given its tracks and what
    /// the account's language settings would pick) as this account's choice
    /// on the server, so every app signed in to it plays them. Returns whether
    /// it's saved.
    func saveTracks(
        for item: MediaItem,
        preferences: LanguagePreferences?,
        choose: @Sendable (_ tracks: ItemTracks, _ automatic: TrackSelection) -> TrackSelection
    ) async -> Bool

    /// Tells the server a stream is no longer needed so it can free transcoder resources.
    func endStream(sessionID: String) async

    func imageURL(for reference: String, size: ImageSize) -> URL?
}

public enum StreamError: Error, Equatable, LocalizedError {
    /// Every copy of the title is missing or unplayable on the server.
    case noPlayableVersion

    public var errorDescription: String? {
        switch self {
        case .noPlayableVersion:
            "The server can't play this title. Its files may have been moved or deleted."
        }
    }
}
