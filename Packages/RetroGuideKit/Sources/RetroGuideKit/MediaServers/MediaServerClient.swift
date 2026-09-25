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

    public init(url: URL, startPosition: TimeInterval, startsAtPosition: Bool, sessionID: String, method: StreamMethod) {
        self.url = url
        self.startPosition = startPosition
        self.startsAtPosition = startsAtPosition
        self.sessionID = sessionID
        self.method = method
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
    ) throws -> StreamRequest

    /// The audio/subtitle tracks the server has selected for this viewer, or `nil`
    /// when unknown (the player then falls back to its own language rules).
    func trackSelection(for item: MediaItem) async -> TrackSelection?

    /// Tells the server a stream is no longer needed so it can free transcoder resources.
    func endStream(sessionID: String) async

    func imageURL(for reference: String, size: ImageSize) -> URL?
}
