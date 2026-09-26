import SwiftUI

/// Scrollable settings page with a large title. Content sits to the left so
/// the picture-in-picture live picture has the bottom-right corner.
private enum SettingsLayout {
    static let contentWidth = PlatformMetric.value(tv: CGFloat(1_150), touch: 720)
    /// Left on Apple TV, beside the picture-in-picture window; centered on
    /// iPhone and iPad, where the window sits below or beside the content.
    static let columnAlignment = PlatformMetric.value(tv: Alignment.leading, touch: .center)
}

struct SettingsPage<Content: View>: View {
    let title: String
    /// Closes Settings from its first page (Menu on Apple TV, Done on iPhone
    /// and iPad). Pages pushed inside Settings leave it `nil` to go back one level.
    var onExit: (() -> Void)?
    @ViewBuilder var content: () -> Content

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pictureInPictureClearance) private var pictureInPictureClearance

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                #if os(tvOS)
                Text(title)
                    .font(Typography.title)
                    .foregroundStyle(theme.textPrimary)
                #endif
                content()
            }
            .columnWidth(SettingsLayout.contentWidth, alignment: .leading)
            .padding(.vertical, DesignTokens.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: SettingsLayout.columnAlignment)
        }
        .screenBackground()
        .crtEffect()
        #if os(tvOS)
        // Focused rows grow slightly; let them draw past the scroll edges.
        .scrollClipDisabled()
        .toolbar(.hidden, for: .navigationBar)
        // Menu goes back one level, or closes Settings from its first page.
        .onExitCommand { (onExit ?? { dismiss() })() }
        #else
        .contentMargins(.leading, DesignTokens.Spacing.md, for: .scrollContent)
        .contentMargins(.trailing, DesignTokens.Spacing.md + pictureInPictureClearance.trailing, for: .scrollContent)
        .contentMargins(.bottom, pictureInPictureClearance.bottom, for: .scrollContent)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if let onExit {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onExit)
                }
            }
        }
        #endif
    }
}

/// A titled group of settings rows.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    @Environment(\.theme) private var theme

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(title.uppercased())
                .font(Typography.captionEmphasis)
                .foregroundStyle(theme.accentSecondary)
            VStack(spacing: DesignTokens.Spacing.sm) {
                content()
            }
            .buttonStyle(.retroRow)
        }
    }
}

/// Icon, title and trailing value, adapting its colors when the row is focused.
struct SettingsRowLabel: View {
    let title: String
    let systemImage: String
    let value: String?
    var accessory: String? = "chevron.right"

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: systemImage)
                .frame(width: DesignTokens.Spacing.xl)
            Text(title)
            Spacer(minLength: DesignTokens.Spacing.md)
            if let value {
                Text(value)
                    .secondaryText()
                    .lineLimit(1)
            }
            if let accessory {
                Image(systemName: accessory)
                    .secondaryText()
            }
        }
    }
}

/// A selectable row with a checkmark, for single- and multi-choice lists.
struct CheckmarkRow: View {
    let title: String
    var detail: String?
    let isSelected: Bool
    let action: () -> Void

    /// iPhone in portrait: the detail goes under the title so neither is squeezed.
    @Environment(\.isNarrowLayout) private var isNarrowLayout

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                if isNarrowLayout {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.hairline) {
                        titleText
                        if let detail {
                            Text(detail).secondaryText()
                        }
                    }
                    Spacer(minLength: .zero)
                } else {
                    titleText
                    Spacer(minLength: DesignTokens.Spacing.md)
                    if let detail {
                        Text(detail).secondaryText()
                    }
                }
            }
        }
        .buttonStyle(.retroRow)
    }

    private var titleText: some View {
        Text(title)
            .lineLimit(1)
    }
}
