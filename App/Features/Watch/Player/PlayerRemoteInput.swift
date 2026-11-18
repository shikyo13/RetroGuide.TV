#if os(tvOS)
import SwiftUI

/// Full-screen Siri Remote handling while watching.
///
/// - Swipe/press up and down: channel up / down
/// - Swipe/press left and right: show what's on now / next
/// - Click: open the guide
/// - Click and hold: Options (always; Down never means anything else)
/// - Back/Menu: open the guide
/// - Play/Pause: jump back to the last channel
struct PlayerRemoteInput: View {
    private enum Timing {
        static let holdDuration: Double = 0.5
    }

    let focus: FocusState<PlayerChromeFocus?>.Binding
    let onCommand: (PlayerCommand) -> Void

    /// A hold opened Options: the release that ends it doesn't also open the guide.
    @State private var didHold = false

    var body: some View {
        Button {
            if didHold { didHold = false } else { onCommand(.openGuide) }
        } label: {
            Color.clear
        }
            .buttonStyle(InvisibleButtonStyle())
            .simultaneousGesture(
                LongPressGesture(minimumDuration: Timing.holdDuration).onEnded { _ in
                    didHold = true
                    onCommand(.openOptions)
                }
            )
            .focused(focus, equals: .remote)
            .onMoveCommand(perform: handleMove)
            .remotePlayPauseCommand { onCommand(.lastChannel) }
            .remoteExitCommand { onCommand(.goBack) }
            .ignoresSafeArea()
    }

    private func handleMove(_ direction: MoveCommandDirection) {
        switch direction {
        case .up: onCommand(.channelUp)
        case .down: onCommand(.channelDown)
        case .left: onCommand(.showNow)
        case .right: onCommand(.showInfo)
        @unknown default: break
        }
    }
}
#endif
