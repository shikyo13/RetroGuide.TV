#if os(tvOS)
import SwiftUI

/// Siri Remote Menu and Play/Pause handlers that DEBUG builds can also fire
/// from a link, because simulator automation can't press those two buttons:
///
///     xcrun simctl openurl booted retroguide://debug/back
///     xcrun simctl openurl booted retroguide://debug/playpause
///
/// A link reaches the handler a real press would: the one nearest the
/// focused view.
extension View {
    func remoteExitCommand(perform action: @escaping () -> Void) -> some View {
        onExitCommand(perform: action)
            #if DEBUG
            .focusedValue(\.debugExitCommand, RemoteCommand(perform: action))
            #endif
    }

    func remotePlayPauseCommand(perform action: @escaping () -> Void) -> some View {
        onPlayPauseCommand(perform: action)
            .focusedValue(\.playPauseCommand, RemoteCommand(perform: action))
    }

    /// Routes system playback commands to the focused control. Development
    /// builds also accept remote-button links for simulator checks.
    func routeRemoteCommands() -> some View {
        modifier(RemoteCommandRouting())
    }
}

struct RemoteCommand {
    let perform: () -> Void
}

extension FocusedValues {
    @Entry var debugExitCommand: RemoteCommand?
    @Entry var playPauseCommand: RemoteCommand?
}

private struct RemoteCommandRouting: ViewModifier {
    #if DEBUG
    private enum Link {
        static let host = "debug"
        static let back = "/back"
        static let playPause = "/playpause"
    }
    #endif

    @FocusedValue(\.debugExitCommand) private var exitCommand
    @FocusedValue(\.playPauseCommand) private var playPauseCommand

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: RemotePlaybackNotification.playPause)) { _ in
            playPauseCommand?.perform()
        }
        #if DEBUG
        .onOpenURL { url in
            guard url.host == Link.host else { return }
            switch url.path {
            case Link.back: exitCommand?.perform()
            case Link.playPause: playPauseCommand?.perform()
            default: break
            }
        }
        #endif
    }
}
#endif
