import SwiftUI

/// A round, icon-only button for compact toolbars on iPhone and iPad. The
/// label's title remains its accessibility label.
struct RetroIconButtonStyle: ButtonStyle {
    /// Apple's minimum comfortable touch target.
    static let diameter: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        RetroIconButtonBody(configuration: configuration)
    }
}

private struct RetroIconButtonBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(Typography.bodyEmphasis)
            .foregroundStyle(isEnabled ? theme.textPrimary : theme.textSecondary.opacity(DesignTokens.Opacity.muted))
            .frame(width: RetroIconButtonStyle.diameter, height: RetroIconButtonStyle.diameter)
            .background(theme.surface, in: Circle())
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? DesignTokens.Scale.pressed : 1)
            .animation(DesignTokens.Motion.quickEase, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == RetroIconButtonStyle {
    static var retroIcon: RetroIconButtonStyle { RetroIconButtonStyle() }
}
