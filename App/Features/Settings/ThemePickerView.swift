import SwiftUI

/// Grid of theme swatches; selecting one applies it immediately.
struct ThemePickerView: View {
    private enum Layout {
        static let columns = 3
        /// Touch: as many columns as fit, each at least this wide.
        static let minimumTouchSwatchWidth: CGFloat = 160
        static let swatchHeight = PlatformMetric.value(tv: CGFloat(220), touch: 120)
    }

    @Environment(AppModel.self) private var app

    var body: some View {
        SettingsPage(title: "Theme") {
            LazyVGrid(columns: columns, spacing: DesignTokens.Spacing.lg) {
                ForEach(ThemeCatalog.all) { theme in
                    Button {
                        app.preferences.themeID = theme.id
                    } label: {
                        ThemeSwatch(theme: theme, isSelected: theme.id == app.preferences.themeID)
                            .frame(height: Layout.swatchHeight)
                    }
                    #if os(tvOS)
                    .buttonStyle(.card)
                    #else
                    .buttonStyle(.plain)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous))
                    #endif
                }
            }
        }
    }

    private var columns: [GridItem] {
        PlatformMetric.value(
            tv: Array(repeating: GridItem(.flexible(), spacing: DesignTokens.Spacing.lg), count: Layout.columns),
            touch: [GridItem(.adaptive(minimum: Layout.minimumTouchSwatchWidth), spacing: DesignTokens.Spacing.lg)]
        )
    }
}

/// A miniature guide rendered in a theme's colors.
private struct ThemeSwatch: View {
    private enum Layout {
        static let barHeight = PlatformMetric.value(tv: CGFloat(26), touch: 14)
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
