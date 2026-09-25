import SwiftUI

/// Full-width list row button used in settings, pickers and channel lists.
struct RetroRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RetroRowBody(configuration: configuration)
    }
}

private struct RetroRowBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isFocused) private var isFocused
    @Environment(\.theme) private var theme

    var body: some View {
        configuration.label
            .font(Typography.body)
            .foregroundStyle(isFocused ? theme.textOnFocus : theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)
                    .fill(isFocused ? theme.focusFill : theme.surface)
            )
            .scaleEffect(isFocused ? DesignTokens.Scale.focused : 1)
            .animation(DesignTokens.Motion.quickEase, value: isFocused)
            .environment(\.rowIsFocused, isFocused)
    }
}

// Lets row content (secondary labels, icons) adapt its colors to focus.
private struct RowIsFocusedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var rowIsFocused: Bool {
        get { self[RowIsFocusedKey.self] }
        set { self[RowIsFocusedKey.self] = newValue }
    }
}

extension ButtonStyle where Self == RetroRowButtonStyle {
    static var retroRow: RetroRowButtonStyle { RetroRowButtonStyle() }
}
