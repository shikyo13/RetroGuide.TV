import SwiftUI

/// Channel number over call sign, the station "bug" used throughout the app.
struct ChannelBadge: View {
    enum Size {
        case regular
        case large

        var numberFont: Font {
            switch self {
            case .regular: Typography.channelNumber
            case .large: Typography.title.monospacedDigit()
            }
        }

        var width: CGFloat {
            switch self {
            case .regular: Layout.regularWidth
            case .large: Layout.largeWidth
            }
        }
    }

    private enum Layout {
        static let regularWidth: CGFloat = 104
        static let largeWidth: CGFloat = 150
    }

    let number: Int
    let callSign: String
    var size: Size = .regular

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xxs) {
            Text(String(number))
                .font(size.numberFont)
                .foregroundStyle(theme.accent)
            Text(callSign)
                .font(Typography.callSign)
                .foregroundStyle(theme.accentSecondary)
                .lineLimit(1)
        }
        .frame(width: size.width)
    }
}
