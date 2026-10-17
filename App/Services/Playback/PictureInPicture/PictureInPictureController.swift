#if os(iOS)
import AVKit
import CoreMedia

/// Picture in Picture for whichever player is in use. It starts by itself
/// when the viewer leaves the app while a channel plays. The window shows
/// live TV: its skip buttons change channel, and pause holds the stream.
@MainActor
final class PictureInPictureController: NSObject {
    private let controller: AVPictureInPictureController
    private(set) var isActive = false
    /// Called with +1 or -1 when the window's skip buttons are used.
    var onChangeChannel: ((Int) -> Void)?
    var onSetPlaying: ((Bool) -> Void)?
    /// Called when the window opens or closes.
    var onActiveChanged: ((Bool) -> Void)?
    /// Called when the window closes (not when the viewer goes back to the app).
    var onClose: (() -> Void)?
    var isPaused = false
    private var isRestoring = false

    /// `nil` where the device doesn't support Picture in Picture.
    init?(engine: any PlaybackEngine) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return nil }
        let relay = PlaybackRelay()
        guard let source = engine.pictureInPictureSource(playbackDelegate: relay) else { return nil }
        controller = AVPictureInPictureController(contentSource: source)
        super.init()
        relay.owner = self
        self.relay = relay
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        // Live TV can't be scrubbed.
        controller.requiresLinearPlayback = engine.kind == .appleNative
    }

    private var relay: PlaybackRelay?

    /// Picture in Picture asks again whether the channel is playing. While
    /// it plays, automatic start is armed afresh: the controller is made at
    /// launch, before the picture is on screen, and iOS only arms automatic
    /// start for a source that's showing.
    func playbackStateChanged(isPlaying: Bool) {
        if isPlaying, !isActive {
            controller.canStartPictureInPictureAutomaticallyFromInline = false
            controller.canStartPictureInPictureAutomaticallyFromInline = true
        }
        controller.invalidatePlaybackState()
    }

    func stop() {
        controller.stopPictureInPicture()
    }

    fileprivate func setPlaying(_ playing: Bool) {
        isPaused = !playing
        onSetPlaying?(playing)
        controller.invalidatePlaybackState()
    }

    fileprivate func skip(by interval: CMTime) {
        onChangeChannel?(interval.seconds < .zero ? -1 : 1)
    }
}

extension PictureInPictureController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated {
            isActive = true
            isRestoring = false
            onActiveChanged?(true)
        }
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        MainActor.assumeIsolated {
            isRestoring = true
        }
        completionHandler(true)
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated {
            isActive = false
            onActiveChanged?(false)
            if !isRestoring {
                onClose?()
            }
            isRestoring = false
        }
    }
}

/// Answers the sample-buffer window's playback questions (RetroGuide Player)
/// on the controller's behalf. AVKit calls these on the main thread.
private final class PlaybackRelay: NSObject, AVPictureInPictureSampleBufferPlaybackDelegate, @unchecked Sendable {
    nonisolated(unsafe) weak var owner: PictureInPictureController?

    func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {
        MainActor.assumeIsolated { owner?.setPlaying(playing) }
    }

    func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        // Live: no beginning or end to scrub between.
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool {
        MainActor.assumeIsolated { owner?.isPaused ?? false }
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    func pictureInPictureController(_ controller: AVPictureInPictureController, skipByInterval skipInterval: CMTime) async {
        await MainActor.run { owner?.skip(by: skipInterval) }
    }
}
#endif
