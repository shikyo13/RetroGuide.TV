import RetroGuideKit
import UIKit

/// Lifecycle events a playback engine reports for the stream it is playing.
enum PlaybackEvent: Equatable, Sendable {
    /// Frames are on screen.
    case playing
    /// The file finished before the schedule expected it to.
    case ended
    case failed(String)
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

    func play(_ request: StreamRequest)
    func stop()
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
