import AVKit
import RetroGuideKit
import UIKit

/// Lifecycle events a playback engine reports for the stream it is playing.
enum PlaybackEvent: Equatable, Sendable {
    /// Frames are on screen.
    case playing
    /// The file finished before the schedule expected it to.
    case ended
    case failed(String)
    /// The video's dynamic range and frame rate, once known.
    case format(VideoFormat)
}

/// The video players RetroGuide can use.
enum PlaybackEngineKind: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Bundled libmpv: plays every file directly from the server.
    case universal
    /// Apple's AVFoundation: direct plays MP4, asks the server to repackage the rest.
    case appleNative

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .universal: "RetroGuide Player"
        case .appleNative: "Apple Player"
        }
    }

    var explanation: String {
        switch self {
        case .universal: "Plays every file directly, with no server transcoding. Recommended."
        case .appleNative: "Uses Apple's player. MKV and other formats are converted by your server."
        }
    }
}

/// A video player that RetroGuide's tuner can drive.
///
/// Engines own a single rendering view; the UI moves that view between full
/// screen and the guide's preview window rather than mirroring it.
@MainActor
protocol PlaybackEngine: AnyObject {
    var kind: PlaybackEngineKind { get }
    var capabilities: PlaybackCapabilities { get }
    var videoView: UIView { get }
    var onEvent: ((PlaybackEvent) -> Void)? { get set }

    /// Plays `request`, honoring the server's audio/subtitle selection when known.
    func play(_ request: StreamRequest, tracks: TrackSelection?)
    func stop()
    /// Holds or continues the stream that's loaded, keeping its place.
    func setPaused(_ paused: Bool)
    /// Whether to output HDR as HDR (the display is in an HDR mode) rather
    /// than converting it to standard range.
    func setPrefersHDROutput(_ prefersHDROutput: Bool)
    /// Whether ``selectTracks(_:)`` switches audio and subtitles while playing.
    var switchesTracksLive: Bool { get }
    func selectTracks(_ tracks: TrackSelection)
    /// Whether ``setSubtitleDelay(_:)`` moves subtitles on what's playing.
    var adjustsSubtitleTiming: Bool { get }
    /// Shows subtitles `seconds` later (earlier when negative), for this and later files.
    func setSubtitleDelay(_ seconds: TimeInterval)
    #if os(iOS)
    /// What Picture in Picture shows for this player (`nil`: it can't).
    func pictureInPictureSource(playbackDelegate: any AVPictureInPictureSampleBufferPlaybackDelegate) -> AVPictureInPictureController.ContentSource?
    /// Whether the Picture in Picture window is showing (frames are needed in the background).
    func setPictureInPictureActive(_ active: Bool)
    #endif
}

extension PlaybackEngine {
    /// Engines that leave HDR handling to the system ignore this.
    func setPrefersHDROutput(_ prefersHDROutput: Bool) {}

    /// Apple's player gets streams the server has already packaged.
    var switchesTracksLive: Bool { false }

    /// Switches audio and subtitles on what's playing, when the engine can.
    func selectTracks(_ tracks: TrackSelection) {}

    /// Apple's player shows subtitles the server has timed.
    var adjustsSubtitleTiming: Bool { false }

    func setSubtitleDelay(_ seconds: TimeInterval) {}

    #if os(iOS)
    func setPictureInPictureActive(_ active: Bool) {}
    #endif
}

@MainActor
enum PlaybackEngineFactory {
    static func make(_ kind: PlaybackEngineKind) -> any PlaybackEngine {
        switch kind {
        case .universal: MPVPlaybackEngine()
        case .appleNative: AVPlaybackEngine()
        }
    }
}
