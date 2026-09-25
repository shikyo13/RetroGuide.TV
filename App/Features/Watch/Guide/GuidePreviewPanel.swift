import RetroGuideKit
import SwiftUI

/// Upper half of the guide: the tuned channel's live picture and details of the focused program.
struct GuidePreviewPanel: View {
    private enum Layout {
        static let logoWidth: CGFloat = 520
        static let logoHeight: CGFloat = 120
        static let summaryLines = 3
        static let backdropFadeStart: CGFloat = 0.1
        static let backdropFadeEnd: CGFloat = 0.9
    }

    let tuner: Tuner
    let channel: Channel?
    let program: ScheduledProgram?

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            livePicture
            details
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: .infinity)
                .background(alignment: .trailing) { backdrop }
                .crtEffect(isFullScreen: false)
        }
        .frame(height: GuideLayout.previewHeight)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.large, style: .continuous))
    }

    /// A placeholder that tells ``WatchView`` where to place the live picture.
    private var livePicture: some View {
        GeometryReader { proxy in
            Color.black
                .preference(key: LivePreviewFrameKey.self, value: proxy.frame(in: .global))
        }
        .aspectRatio(GuideLayout.previewAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.large, style: .continuous))
    }

    @ViewBuilder
    private var details: some View {
        if let program, let channel {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text("\(channel.number) · \(channel.name)")
                        .font(Typography.callout)
                        .foregroundStyle(theme.accentSecondary)
                    RatingChip(rating: program.item.contentRating, audience: program.item.audience)
                }
                title(for: program)
                if let subheadline = program.item.subheadline {
                    Text(subheadline)
                        .font(Typography.bodyEmphasis)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                }
                Text(timing(for: program))
                    .font(Typography.clock)
                    .foregroundStyle(theme.accent)
                if let summary = program.item.summary {
                    Text(summary)
                        .font(Typography.caption)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(Layout.summaryLines)
                }
            }
            .id(program.id)
            .transition(.opacity)
        }
    }

    private func title(for program: ScheduledProgram) -> some View {
        RemoteImage(
            serverID: program.item.serverID,
            reference: program.item.artwork.logo,
            size: ArtworkSize.logo,
            contentMode: .fit
        ) {
            Text(program.item.headline)
                .font(Typography.title)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: Layout.logoWidth, maxHeight: Layout.logoHeight, alignment: .leading)
    }

    private func timing(for program: ScheduledProgram) -> String {
        let now = Date.now
        let range = ScheduleFormatting.range(program)
        if program.contains(now) {
            return "\(range) · \(ScheduleFormatting.remaining(in: program, at: now))"
        }
        return "\(range) · \(ScheduleFormatting.duration(program.item.duration))"
    }

    @ViewBuilder
    private var backdrop: some View {
        if let program {
            RemoteImage(serverID: program.item.serverID, reference: program.item.artwork.backdrop, size: ArtworkSize.backdrop)
                .opacity(DesignTokens.Opacity.muted)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: Layout.backdropFadeStart),
                            .init(color: .black, location: Layout.backdropFadeEnd),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .id(program.item.artwork.backdrop)
        }
    }
}
