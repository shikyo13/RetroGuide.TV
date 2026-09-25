import Foundation

/// The audio and subtitle tracks the media server wants played for an item,
/// reflecting the viewer's language preferences and per-item choices.
public struct TrackSelection: Sendable, Hashable {
    /// Container stream index of the selected audio track, if the server chose one.
    public let audioStreamIndex: Int?
    public let subtitle: SubtitleChoice

    public init(audioStreamIndex: Int?, subtitle: SubtitleChoice) {
        self.audioStreamIndex = audioStreamIndex
        self.subtitle = subtitle
    }
}

public enum SubtitleChoice: Sendable, Hashable {
    /// Subtitles are off.
    case none
    /// A subtitle stream inside the media file, by container stream index.
    case embedded(streamIndex: Int)
    /// A sidecar subtitle file served separately.
    case external(URL)
}
