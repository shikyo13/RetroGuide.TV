#if os(tvOS)
import SwiftUI

/// Full-screen Siri Remote handling while watching.
///
/// - Swipe/press up and down: channel up / down
/// - Swipe/press left and right: show what's on now / next
/// - Click: open the guide
/// - Play/Pause: jump back to the last channel
struct PlayerRemoteInput: View {
    let onCommand: (PlayerCommand) -> Void

    @FocusState private var hasRemoteFocus: Bool

    var body: some View {
        Button {
            onCommand(.openGuide)
        } label: {
            Color.clear
        }
        .buttonStyle(InvisibleButtonStyle())
        .focused($hasRemoteFocus)
        .onMoveCommand(perform: handleMove)
        .onPlayPauseCommand { onCommand(.lastChannel) }
        .ignoresSafeArea()
        .onAppear { hasRemoteFocus = true }
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
