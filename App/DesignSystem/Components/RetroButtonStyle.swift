import SwiftUI

/// The app's standard focusable button: a themed capsule that fills with the
/// focus color and lifts slightly when focused.
struct RetroButtonStyle: ButtonStyle {
    enum Prominence {
        case primary
        case secondary
    }

    var prominence: Prominence = .secondary

    func makeBody(configuration: Configuration) -> some View {
        RetroButtonBody(configuration: configuration, prominence: prominence)
    }
}

private struct RetroButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominence: RetroButtonStyle.Prominence

    @Environment(\.isFocused) private var isFocused
    @Environment(\.theme) private var theme

    var body: some View {
        configuration.label
            .font(Typography.bodyEmphasis)
            .foregroundStyle(isFocused ? theme.textOnFocus : theme.textPrimary)
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(background)
            .clipShape(Capsule())
            .scaleEffect(scale)
            .shadow(
                color: .black.opacity(isFocused ? DesignTokens.Shadow.opacity : .zero),
                radius: DesignTokens.Shadow.radius,
                y: DesignTokens.Shadow.offsetY
            )
            .animation(DesignTokens.Motion.quickEase, value: isFocused)
            .animation(DesignTokens.Motion.quickEase, value: configuration.isPressed)
    }

    private var background: Color {
        if isFocused { return theme.focusFill }
        return prominence == .primary ? theme.surfaceRaised : theme.surface
    }

    private var scale: CGFloat {
        if configuration.isPressed { return DesignTokens.Scale.pressed }
        return isFocused ? DesignTokens.Scale.focused : 1
    }
}

extension ButtonStyle where Self == RetroButtonStyle {
    static var retro: RetroButtonStyle { RetroButtonStyle() }
    static var retroPrimary: RetroButtonStyle { RetroButtonStyle(prominence: .primary) }
}
