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
    var isIndependent = false
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
            .accessibilityLabel(isIndependent ? "Watching from beginning" : "Live TV")
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

/// On-screen buttons shown with the info banner on iPhone and iPad: Guide is
/// the one highlighted button; the rest are icons with short captions.
struct PlayerTouchControls: View {
    let onCommand: (PlayerCommand) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            Button {
                onCommand(.openGuide)
            } label: {
                Label("Guide", systemImage: "list.bullet.rectangle")
                    // One line in every language ("TV-Programm" wrapped mid-word):
                    // it gets the row's spare width first, then shrinks a little.
                    .lineLimit(1)
                    .minimumScaleFactor(Typography.minimumScaleFactor)
            }
            .buttonStyle(.retroPrimary)
            .layoutPriority(1)
            Spacer(minLength: DesignTokens.Spacing.md)
            CaptionedIconButton(String(localized: "Options"), caption: String(localized: "Options"), systemImage: "slider.horizontal.3") {
                onCommand(.openOptions)
            }
            CaptionedIconButton(String(localized: "Last channel"), caption: String(localized: "Last", comment: "Short caption under the last-channel button"), systemImage: "arrow.left.arrow.right") {
                onCommand(.lastChannel)
            }
            CaptionedIconButton(String(localized: "Channel down"), caption: String(localized: "Ch −", comment: "Short caption under the channel-down button"), systemImage: "chevron.down") {
                onCommand(.channelDown)
            }
            CaptionedIconButton(String(localized: "Channel up"), caption: String(localized: "Ch +", comment: "Short caption under the channel-up button"), systemImage: "chevron.up") {
                onCommand(.channelUp)
            }
        }
    }
}

/// A round icon button with a short caption under it; `title` stays its
/// accessibility label.
private struct CaptionedIconButton: View {
    let title: String
    let caption: String
    let systemImage: String
    let action: () -> Void

    @Environment(\.theme) private var theme

    init(_ title: String, caption: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.caption = caption
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xxs) {
            Button(action: action) {
                Label(title, systemImage: systemImage)
            }
            .buttonStyle(.retroIcon)
            Text(caption)
                .font(Typography.micro)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .accessibilityHidden(true)
        }
    }
}
#endif
