#if os(iOS)
import SwiftUI

/// Full-screen touch handling while watching on iPhone and iPad, mirroring the
/// Siri Remote:
///
/// - Swipe up / down: channel up / down
/// - Swipe right / left: show what's on now / next
/// - Tap: show or hide the info banner and on-screen controls
struct PlayerTouchInput: View {
    let isInfoVisible: Bool
    let onCommand: (PlayerCommand) -> Void

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    onCommand(isInfoVisible ? .hideInfo : .showNow)
                }
                .gesture(
                    DragGesture(minimumDistance: TouchGesture.minimumDistance)
                        .onEnded { value in
                            // With the home indicator hidden, iOS hands the first edge
                            // swipe to the app; leave those to the system.
                            guard !Self.startsAtSystemEdge(value.startLocation, height: proxy.size.height) else { return }
                            handleSwipe(value.translation)
                        }
                )
        }
        .ignoresSafeArea()
            .accessibilityElement()
            .accessibilityLabel("Live TV")
            .accessibilityHint("Double-tap for controls. Swipe up or down to change channel.")
            .accessibilityAction {
                onCommand(isInfoVisible ? .hideInfo : .showNow)
            }
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onCommand(.channelUp)
                case .decrement: onCommand(.channelDown)
                @unknown default: break
                }
            }
    }

    private static func startsAtSystemEdge(_ location: CGPoint, height: CGFloat) -> Bool {
        location.y < TouchGesture.systemEdgeMargin || location.y > height - TouchGesture.systemEdgeMargin
    }

    private func handleSwipe(_ translation: CGSize) {
        switch SwipeDirection(translation: translation) {
        case .up: onCommand(.channelUp)
        case .down: onCommand(.channelDown)
        case .left: onCommand(.showNext)
        case .right: onCommand(.showNow)
        case nil: break
        }
    }
}

/// On-screen buttons shown with the info banner on iPhone and iPad.
struct PlayerTouchControls: View {
    let onCommand: (PlayerCommand) -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Button {
                onCommand(.openGuide)
            } label: {
                Label("Guide", systemImage: "list.bullet.rectangle")
            }
            .buttonStyle(.retroPrimary)
            Spacer(minLength: DesignTokens.Spacing.md)
            Button {
                onCommand(.lastChannel)
            } label: {
                Label("Last channel", systemImage: "arrow.uturn.backward")
            }
            Button {
                onCommand(.channelDown)
            } label: {
                Label("Channel down", systemImage: "chevron.down")
            }
            Button {
                onCommand(.channelUp)
            } label: {
                Label("Channel up", systemImage: "chevron.up")
            }
        }
        .buttonStyle(.retroIcon)
    }
}
#endif
