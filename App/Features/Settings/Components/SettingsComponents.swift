import SwiftUI

/// Scrollable settings page with a large title. Content sits to the left so
/// the picture-in-picture live picture has the bottom-right corner.
private enum SettingsLayout {
    static let contentWidth: CGFloat = 1_150
}

struct SettingsPage<Content: View>: View {
    let title: String
    /// Called when Menu is pressed on this page. Pages pushed inside Settings
    /// leave it `nil` to simply go back one level.
    var onExit: (() -> Void)?
    @ViewBuilder var content: () -> Content

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                Text(title)
                    .font(Typography.title)
                    .foregroundStyle(theme.textPrimary)
                content()
            }
            .frame(width: SettingsLayout.contentWidth, alignment: .leading)
            .padding(.vertical, DesignTokens.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollClipDisabled()
        .screenBackground()
        .crtEffect()
        .toolbar(.hidden, for: .navigationBar)
        // Menu goes back one level, or closes Settings from its first page.
        .onExitCommand { (onExit ?? { dismiss() })() }
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: DesignTokens.Spacing.md)
                if let detail {
                    Text(detail).secondaryText()
                }
            }
        }
        .buttonStyle(.retroRow)
    }
}
