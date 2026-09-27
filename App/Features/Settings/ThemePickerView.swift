import SwiftUI

/// Grid of theme swatches; selecting one applies it immediately. Pro themes
/// show a lock and open the upgrade page until RetroGuide Pro is purchased.
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
                    if theme.id.isIncludedFree || app.pro.isPro {
                        Button {
                            app.preferences.themeID = theme.id
                        } label: {
                            swatch(for: theme, isLocked: false)
                        }
                        .themeSwatchStyle()
                    } else {
                        NavigationLink {
                            ProUpgradeView()
                        } label: {
                            swatch(for: theme, isLocked: true)
                        }
                        .themeSwatchStyle()
                    }
                }
            }
        }
    }

    private func swatch(for theme: Theme, isLocked: Bool) -> some View {
        ThemeSwatch(theme: theme, isSelected: theme.id == app.theme.id, isLocked: isLocked)
            .frame(height: Layout.swatchHeight)
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
    let isLocked: Bool

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
                } else if isLocked {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(theme.textSecondary)
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

private extension View {
    /// Card focus on Apple TV; a plain rounded tile on iPhone and iPad.
    @ViewBuilder
    func themeSwatchStyle() -> some View {
        #if os(tvOS)
        buttonStyle(.card)
        #else
        buttonStyle(.plain)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous))
        #endif
    }
}
