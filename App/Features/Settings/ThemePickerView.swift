import SwiftUI

/// Grid of theme swatches; selecting one applies it immediately.
struct ThemePickerView: View {
    private enum Layout {
        static let columns = 3
        static let swatchHeight: CGFloat = 220
    }

    @Environment(AppModel.self) private var app

    var body: some View {
        SettingsPage(title: "Theme") {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: DesignTokens.Spacing.lg), count: Layout.columns),
                spacing: DesignTokens.Spacing.lg
            ) {
                ForEach(ThemeCatalog.all) { theme in
                    Button {
                        app.preferences.themeID = theme.id
                    } label: {
                        ThemeSwatch(theme: theme, isSelected: theme.id == app.preferences.themeID)
                            .frame(height: Layout.swatchHeight)
                    }
                    .buttonStyle(.card)
                }
            }
        }
    }
}

/// A miniature guide rendered in a theme's colors.
private struct ThemeSwatch: View {
    private enum Layout {
        static let barHeight: CGFloat = 26
        static let focusedBarWidthFraction: CGFloat = 0.55
    }

    let theme: Theme
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack {
                Text(theme.name)
                    .font(Typography.bodyEmphasis)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.accent)
                }
            }
            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                        .fill(theme.focusFill)
                        .frame(width: proxy.size.width * Layout.focusedBarWidthFraction, height: Layout.barHeight)
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                        .fill(theme.surfaceRaised)
                        .frame(height: Layout.barHeight)
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                        .fill(theme.surface)
                        .frame(height: Layout.barHeight)
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(theme.backgroundGradient)
    }
}
