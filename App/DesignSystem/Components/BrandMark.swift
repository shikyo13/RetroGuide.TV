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

        /// Glyph width, proportional to the text size so both sizes look identical.
        var glyphWidth: CGFloat {
            switch self {
            case .compact: Typography.Size.headline * BrandMark.glyphToTextRatio
            case .large: Typography.Size.display * BrandMark.glyphToTextRatio
            }
        }
    }

    /// Glyph width as a fraction of the font size (also used by the app icon generator).
    nonisolated static let glyphToTextRatio: CGFloat = 1.1

    var size: Size = .compact

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            TVGlyph()
                .brandFill(theme.accent)
                .frame(width: size.glyphWidth)
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
