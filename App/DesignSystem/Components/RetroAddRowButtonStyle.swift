import SwiftUI

/// A list row for adding something: a dashed outline in the accent color,
/// reading as an empty slot rather than another button. Fills like any row
/// when focused.
struct RetroAddRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RetroAddRowBody(configuration: configuration)
    }
}

private struct RetroAddRowBody: View {
    private enum Layout {
        static let dash = PlatformMetric.value(tv: CGFloat(10), touch: 6)
    }

    let configuration: ButtonStyleConfiguration

    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.theme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)
        configuration.label
            .font(Typography.settingsBody)
            .foregroundStyle(isFocused ? theme.textOnFocus : theme.accentSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .frame(minHeight: DesignTokens.Control.minimumHeight)
            .background(shape.fill(isFocused ? theme.focusFill : .clear))
            .overlay(
                shape.strokeBorder(
                    theme.accentSecondary,
                    style: StrokeStyle(lineWidth: DesignTokens.Stroke.thin, dash: [Layout.dash])
                )
                .opacity(isFocused ? 0 : 1)
            )
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? DesignTokens.Scale.pressed : (isFocused ? DesignTokens.Scale.focused : 1))
            .animation(DesignTokens.Motion.quickEase, value: isFocused)
            .environment(\.rowIsFocused, isFocused)
            .opacity(isEnabled ? 1 : DesignTokens.Opacity.muted)
    }
}

extension ButtonStyle where Self == RetroAddRowButtonStyle {
    static var retroAddRow: RetroAddRowButtonStyle { RetroAddRowButtonStyle() }
}
