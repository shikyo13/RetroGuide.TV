import MediaPlayer
import RetroGuideKit

/// Tells the system what's on (Control Center, the lock screen) and makes
/// RetroGuide.TV the Now Playing app. On Apple TV this is what lets the
/// Control Center speaker picker (HomePod, AirPlay) move the app's audio.
@MainActor
final class NowPlayingPublisher {
    struct Actions {
        let play: () -> Void
        let pause: () -> Void
        let channelUp: () -> Void
        let channelDown: () -> Void
    }

    private enum Rate {
        static let playing = 1.0
        static let stopped = 0.0
    }

    private let center = MPNowPlayingInfoCenter.default()
    private var commandTargets: [(MPRemoteCommand, Any)] = []

    init(actions: Actions) {
        let commands = MPRemoteCommandCenter.shared()
        register(commands.playCommand) { actions.play() }
        register(commands.pauseCommand) { actions.pause() }
        register(commands.nextTrackCommand) { actions.channelUp() }
        register(commands.previousTrackCommand) { actions.channelDown() }
    }

    isolated deinit {
        for (command, target) in commandTargets {
            command.removeTarget(target)
        }
    }

    /// Publishes the program on `channel`, or clears Now Playing when nothing is on.
    func update(channel: Channel?, program: ScheduledProgram?, isPlaying: Bool) {
        guard let channel, let program else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        center.nowPlayingInfo = [
            MPMediaItemPropertyTitle: program.item.headline,
            MPMediaItemPropertyArtist: channel.name,
            MPMediaItemPropertyPlaybackDuration: program.contentEnd.timeIntervalSince(program.start),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Date.now.timeIntervalSince(program.start),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Rate.playing : Rate.stopped,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
        center.playbackState = isPlaying ? .playing : .paused
    }

    private func register(_ command: MPRemoteCommand, perform action: @escaping @MainActor () -> Void) {
        command.isEnabled = true
        let target = command.addTarget { _ in
            MainActor.assumeIsolated { action() }
            return .success
        }
        commandTargets.append((command, target))
    }
}
