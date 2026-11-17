import SwiftUI

/// A localized one-line sentence with a price in it, the price laid out on its
/// own so it gets the standard font. Text in some scripts (Odia) is drawn with
/// that script's font, whose Latin digits have their own shapes: "$9.99" set
/// inside it can read as a different number.
struct PriceText: View {
    let price: String
    /// Builds the localized sentence around what it's given; called with a
    /// marker to find where the price goes.
    let format: (String) -> String

    var body: some View {
        let parts = format(Self.marker).components(separatedBy: Self.marker)
        if parts.count == 2 {
            HStack(spacing: DesignTokens.Spacing.xs) {
                fragment(parts[0])
                Text(verbatim: price)
                    .font(Self.latinDigitsFont)
                fragment(parts[1])
            }
        } else {
            Text(verbatim: format(price))
        }
    }

    @ViewBuilder
    private func fragment(_ text: String) -> some View {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { Text(verbatim: trimmed) }
    }

    /// App languages whose system font draws Latin digits in the script's own
    /// style (Odia's "9" looks like its "2"). The price uses a Latin font there;
    /// elsewhere it keeps the surrounding font (nil).
    private static let latinDigitsFont: Font? = {
        let shown = Bundle.main.preferredLocalizations.first ?? ""
        guard Typography.LatinDigits.languages.contains(shown) else { return nil }
        return .custom(Typography.LatinDigits.fontName, size: Typography.Size.body)
    }()
    /// Unlikely in any translation; stands in for the price.
    private static let marker = "\u{E000}"
}
