import RetroGuideKit
import SwiftUI

/// Bottom "info bar" showing the channel and what's on now (or next).
struct ChannelBanner: View {
    private enum Layout {
        static let logoWidth = PlatformMetric.value(tv: CGFloat(360), touch: 150)
        static let logoHeight = PlatformMetric.value(tv: CGFloat(110), touch: 46)
        static let summaryLines = 2
        static let progressHeight = PlatformMetric.value(tv: CGFloat(8), touch: 5)
    }

    let channel: Channel
    let program: ScheduledProgram?
    let isShowingNext: Bool

    @Environment(\.theme) private var theme
    /// iPhone in portrait: too narrow for the badge, details and logo side by side.
    @Environment(\.isNarrowLayout) private var isStacked

    var body: some View {
        TimelineView(.periodic(from: .now, by: ScheduleConstants.secondsPerMinute)) { context in
            Group {
                if isStacked {
                    stackedLayout(now: context.date)
                } else {
                    wideLayout(now: context.date)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .panel()
            .background(theme.scrim, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.large))
        }
    }

    private func wideLayout(now: Date) -> some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.lg) {
            ChannelBadge(number: channel.number, callSign: channel.callSign, size: .large)
            Divider().overlay(theme.textSecondary.opacity(DesignTokens.Opacity.muted))
            if let program {
                details(program, now: now)
            } else {
                channelName
            }
            Spacer(minLength: DesignTokens.Spacing.md)
            if let program {
                logo(for: program)
            }
        }
    }

    private func stackedLayout(now: Date) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
                ChannelBadge(number: channel.number, callSign: channel.callSign)
                Spacer(minLength: DesignTokens.Spacing.md)
                if let program {
                    logo(for: program)
                }
            }
            if let program {
                details(program, now: now)
            } else {
                channelName
            }
        }
    }

    private var channelName: some View {
        Text(channel.name).font(Typography.headline).foregroundStyle(theme.textPrimary)
    }

    private func details(_ program: ScheduledProgram, now: Date) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Text(isShowingNext ? "UP NEXT" : "NOW")
                    .font(Typography.captionEmphasis)
                    .foregroundStyle(theme.textOnFocus)
                    .padding(.horizontal, DesignTokens.Spacing.xs)
                    .background(theme.accent, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.small))
                Text(channel.name)
                    .font(Typography.caption)
                    .foregroundStyle(theme.accentSecondary)
                    .lineLimit(1)
                RatingChip(rating: program.item.contentRating, audience: program.item.audience)
            }
            Text(program.item.headline)
                .font(Typography.headline)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
            if let subheadline = program.item.subheadline {
                Text(subheadline)
                    .font(Typography.callout)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
            if let summary = program.item.summary, !summary.isEmpty {
                Text(summary)
                    .font(Typography.caption)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(Layout.summaryLines)
            }
            HStack(spacing: DesignTokens.Spacing.md) {
                Text(ScheduleFormatting.range(program))
                    .font(Typography.clock)
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize()
                if !isShowingNext {
                    ProgressTrack(progress: program.progress(at: now), height: Layout.progressHeight)
                    Text(ScheduleFormatting.remaining(in: program, at: now))
                        .font(Typography.caption)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize()
                }
            }
            #if os(tvOS)
            RemoteHints()
            #endif
        }
    }

    private func logo(for program: ScheduledProgram) -> some View {
        RemoteImage(
            serverID: program.item.serverID,
            reference: program.item.artwork.logo,
            size: ArtworkSize.logo,
            contentMode: .fit
        )
        .frame(width: Layout.logoWidth, height: Layout.logoHeight)
    }
}

#if os(tvOS)
/// A compact legend of remote controls. On iPhone and iPad the on-screen
/// controls take its place.
struct RemoteHints: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            hint("chevron.up.chevron.down", "Channel")
            hint("chevron.left.chevron.right", "Now / Next")
            hint("circle.circle", "Guide")
            hint("playpause", "Last channel")
        }
        .font(Typography.micro)
        .foregroundStyle(theme.textSecondary.opacity(DesignTokens.Opacity.strong))
    }

    private func hint(_ symbol: String, _ label: String) -> some View {
        Label(label, systemImage: symbol)
    }
}
#endif
