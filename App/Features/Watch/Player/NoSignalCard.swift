import SwiftUI

/// Classic color bars with a "No Signal" slate, shown when a stream fails.
struct NoSignalCard: View {
    private enum Layout {
        static let slateWidth = PlatformMetric.value(tv: CGFloat(1_100), touch: 520)
        static let mainBarsFraction: CGFloat = 0.67
    }

    /// SMPTE-style bar colors, left to right.
    private static let bars: [Color] = [
        Color(hex: "#C0C0C0"), Color(hex: "#C0C000"), Color(hex: "#00C0C0"), Color(hex: "#00C000"),
        Color(hex: "#C000C0"), Color(hex: "#C00000"), Color(hex: "#0000C0"),
    ]
    private static let lowerBars: [Color] = [
        Color(hex: "#0000C0"), Color(hex: "#131313"), Color(hex: "#C000C0"), Color(hex: "#131313"),
        Color(hex: "#00C0C0"), Color(hex: "#131313"), Color(hex: "#C0C0C0"),
    ]

    let message: String

    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: .zero) {
                barRow(Self.bars)
                    .frame(height: proxy.size.height * Layout.mainBarsFraction)
                barRow(Self.lowerBars)
            }
        }
        .ignoresSafeArea()
        .overlay {
            VStack(spacing: DesignTokens.Spacing.md) {
                Text("NO SIGNAL")
                    .font(Typography.display.monospaced())
                    .foregroundStyle(theme.textPrimary)
                Text(message)
                    .font(Typography.body)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                Text("Retrying automatically…")
                    .font(Typography.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            .columnWidth(Layout.slateWidth)
            .panel(padding: DesignTokens.Spacing.xl)
            .background(Color.black.opacity(DesignTokens.Opacity.scrim), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.large))
        }
    }

    private func barRow(_ colors: [Color]) -> some View {
        HStack(spacing: .zero) {
            ForEach(colors.indices, id: \.self) { index in
                colors[index]
            }
        }
    }
}
