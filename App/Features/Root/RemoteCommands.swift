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
            #if DEBUG
            .focusedValue(\.debugPlayPauseCommand, RemoteCommand(perform: action))
            #endif
    }

    /// Runs the focused handler for `retroguide://debug/…` links; added once, at the root.
    func debugRemoteLinks() -> some View {
        #if DEBUG
        modifier(DebugRemoteLinks())
        #else
        self
        #endif
    }
}

struct RemoteCommand {
    let perform: () -> Void
}

extension FocusedValues {
    @Entry var debugExitCommand: RemoteCommand?
    @Entry var debugPlayPauseCommand: RemoteCommand?
}

#if DEBUG
private struct DebugRemoteLinks: ViewModifier {
    private enum Link {
        static let host = "debug"
        static let back = "/back"
        static let playPause = "/playpause"
    }

    @FocusedValue(\.debugExitCommand) private var exitCommand
    @FocusedValue(\.debugPlayPauseCommand) private var playPauseCommand

    func body(content: Content) -> some View {
        content.onOpenURL { url in
            guard url.host == Link.host else { return }
            switch url.path {
            case Link.back: exitCommand?.perform()
            case Link.playPause: playPauseCommand?.perform()
            default: break
            }
        }
    }
}
#endif
#endif
