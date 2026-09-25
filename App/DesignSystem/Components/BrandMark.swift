import SwiftUI

/// The RetroGuide.TV wordmark: a small TV glyph, "RetroGuide" and an accented ".TV".
struct BrandMark: View {
    enum Size {
        case compact
        case large

        var font: Font {
            switch self {
            case .compact: Typography.headline
            case .large: Typography.display
            }
        }
    }

    var size: Size = .compact

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "tv.inset.filled")
                .foregroundStyle(theme.accent)
            Text(AppIdentity.Wordmark.name)
                .foregroundStyle(theme.textPrimary)
            + Text(AppIdentity.Wordmark.suffix)
                .foregroundStyle(theme.accent)
        }
        .font(size.font)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AppIdentity.productName)
    }
}
