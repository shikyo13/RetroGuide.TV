import SwiftUI

/// The big glowing channel number in the corner, like an old TV's on-screen display.
struct ChannelNumberOSD: View {
    private enum Style {
        static let glowRadius: CGFloat = 12
        static let outlineRadius: CGFloat = 2
    }

    let number: Int
    let callSign: String

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .trailing, spacing: .zero) {
            Text(String(number))
                .font(Typography.osd)
            Text(callSign)
                .font(Typography.headline.monospaced())
        }
        .foregroundStyle(theme.osd)
        .shadow(color: .black, radius: Style.outlineRadius)
        .shadow(color: theme.osd.opacity(DesignTokens.Opacity.muted), radius: Style.glowRadius)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Channel \(number), \(callSign)")
    }
}
