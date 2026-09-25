import SwiftUI

/// Full-screen themed background (ignores safe areas).
struct ScreenBackground: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content.background(theme.backgroundGradient.ignoresSafeArea())
    }
}

/// Rounded, themed container used for panels and cards.
struct PanelBackground: ViewModifier {
    var padding: CGFloat = DesignTokens.Spacing.lg

    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.large, style: .continuous)
                    .fill(theme.surface.opacity(DesignTokens.Opacity.strong))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.large, style: .continuous)
                    .strokeBorder(theme.textPrimary.opacity(DesignTokens.Opacity.faint), lineWidth: DesignTokens.Stroke.thin)
            )
    }
}

/// Secondary text that stays legible on a focused (inverted) row.
struct SecondaryText: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.rowIsFocused) private var rowIsFocused

    func body(content: Content) -> some View {
        content
            .font(Typography.caption)
            .foregroundStyle(rowIsFocused ? theme.textOnFocus.opacity(DesignTokens.Opacity.strong) : theme.textSecondary)
    }
}

extension View {
    func screenBackground() -> some View {
        modifier(ScreenBackground())
    }

    func panel(padding: CGFloat = DesignTokens.Spacing.lg) -> some View {
        modifier(PanelBackground(padding: padding))
    }

    func secondaryText() -> some View {
        modifier(SecondaryText())
    }
}
