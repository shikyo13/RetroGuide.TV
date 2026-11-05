import SwiftUI
import UIKit

/// Program information remains visible before a Home Screen card receives focus.
struct TopShelfCard: View {
    enum Layout {
        static let width: CGFloat = 840
        static let height: CGFloat = 472.5
        static let badgeInset: CGFloat = 24
        static let gradientHeight: CGFloat = 230
        static let gradientShoulder: CGFloat = 0.28
        static let gradientOpacity: Double = 0.82
        // tvOS draws its playback progress bar below the program information.
        static let progressClearance: CGFloat = 48
    }

    let channel: WhatsOnSnapshot.Channel
    let program: WhatsOnSnapshot.Program
    let artwork: UIImage?

    @Environment(\.theme) private var theme

    private var background: Color { theme.backgroundColors.last ?? .black }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            background
            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Layout.width, height: Layout.height)
                    .clipped()
            }
            LinearGradient(stops: [
                .init(color: .clear, location: .zero),
                .init(color: background.opacity(Layout.gradientOpacity), location: Layout.gradientShoulder),
                .init(color: background, location: 1)
            ], startPoint: .top, endPoint: .bottom)
            .frame(height: Layout.gradientHeight)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(channel.name)
                    .font(Typography.caption)
                    .foregroundStyle(theme.accentSecondary)
                    .lineLimit(1)
                Text(program.title)
                    .font(Typography.headline)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(Typography.minimumScaleFactor)
                if let episode = program.episode, !episode.isEmpty {
                    Text(episode)
                        .font(Typography.callout)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.bottom, Layout.progressClearance)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            ChannelBadge(number: channel.number, callSign: channel.callSign, size: .large)
                .panel(padding: DesignTokens.Spacing.sm)
                .background(theme.scrim, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.large))
                .padding(Layout.badgeInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: Layout.width, height: Layout.height)
        .clipped()
    }
}
