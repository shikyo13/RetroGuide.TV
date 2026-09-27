import RetroGuideKit
import SwiftUI

/// Upper half of the guide: the tuned channel's live picture and details of the focused program.
/// On iPhone it shrinks to one compact row so the channel grid keeps most of the screen.
struct GuidePreviewPanel: View {
    private enum Layout {
        static let logoWidth = PlatformMetric.value(tv: CGFloat(520), touch: 260)
        static let logoHeight = PlatformMetric.value(tv: CGFloat(120), touch: 56)
        /// Phones: a smaller logo fits the compact row.
        static let compactLogoHeight: CGFloat = 30
        static let summaryLines = PlatformMetric.value(tv: 3, touch: 2)
        static let backdropFadeStart: CGFloat = 0.1
        static let backdropFadeEnd: CGFloat = 0.9
    }

    let tuner: Tuner
    let channel: Channel?
    let program: ScheduledProgram?
    /// Touch only: tunes to the focused channel.
    var onWatch: (() -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.isNarrowLayout) private var isNarrow
    @Environment(\.isShortLayout) private var isShort

    /// iPhone in either orientation: a short row without the summary.
    private var isCompact: Bool {
        isNarrow || isShort
    }

    var body: some View {
        HStack(spacing: isCompact ? DesignTokens.Spacing.sm : DesignTokens.Spacing.lg) {
            livePicture
            details
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: .infinity)
                .background(alignment: .trailing) { backdrop }
                .crtEffect(isFullScreen: false)
        }
        .frame(height: panelHeight)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.large, style: .continuous))
    }

    private var panelHeight: CGFloat {
        if isShort { return GuideLayout.shortPreviewHeight }
        return isNarrow ? GuideLayout.compactPreviewHeight : GuideLayout.previewHeight
    }

    /// A placeholder that tells ``WatchView`` where to place the live picture.
    /// On iPhone and iPad, tapping it watches the focused channel full screen.
    private var livePicture: some View {
        GeometryReader { proxy in
            Color.black
                .preference(key: LivePreviewFrameKey.self, value: proxy.frame(in: .global))
        }
        .aspectRatio(GuideLayout.previewAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.large, style: .continuous))
        #if os(iOS)
        .contentShape(Rectangle())
        .onTapGesture { onWatch?() }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Watch full screen")
        #endif
    }

    @ViewBuilder
    private var details: some View {
        if let program, let channel {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                // Landscape phones: the picture's channel badge and the grid already name the channel.
                if !isShort {
                    channelLine(channel, program: program)
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
                    .lineLimit(1)
                    .minimumScaleFactor(Typography.minimumScaleFactor)
                if let summary = program.item.summary, !isCompact {
                    Text(summary)
                        .font(Typography.caption)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(Layout.summaryLines)
                }
                if let onWatch, !isCompact {
                    Button(action: onWatch) {
                        Label("Watch channel \(channel.number)", systemImage: "play.fill")
                    }
                    .buttonStyle(.retroPrimary)
                }
            }
            .id(program.id)
            .transition(.opacity)
        }
    }

    private func channelLine(_ channel: Channel, program: ScheduledProgram) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Text("\(channel.number) · \(channel.name)")
                .font(Typography.callout)
                .foregroundStyle(theme.accentSecondary)
                .lineLimit(1)
            RatingChip(rating: program.item.contentRating, audience: program.item.audience)
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
                .font(isCompact ? Typography.headline : Typography.title)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: Layout.logoWidth, maxHeight: isCompact ? Layout.compactLogoHeight : Layout.logoHeight, alignment: .leading)
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
