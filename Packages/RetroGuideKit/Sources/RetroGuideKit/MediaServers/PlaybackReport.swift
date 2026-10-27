import Foundation

/// A snapshot of actual playback, including the chosen copy and its tracks.
public struct PlaybackReport: Sendable {
    public enum Event: Sendable { case started, progress, stopped }
    public let event: Event
    public let item: MediaItem
    public let request: StreamRequest
    public let position: TimeInterval
    public let isPaused: Bool
    public let tracks: ItemTracks?
    public let selection: TrackSelection?

    public init(event: Event, item: MediaItem, request: StreamRequest, position: TimeInterval,
                isPaused: Bool = false, tracks: ItemTracks?, selection: TrackSelection?) {
        self.event = event
        self.item = item
        self.request = request
        self.position = position.isFinite ? max(.zero, position) : .zero
        self.isPaused = isPaused
        self.tracks = tracks
        self.selection = selection
    }
}
