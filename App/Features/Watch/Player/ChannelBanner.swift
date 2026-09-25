import RetroTVKit
import SwiftUI

/// Bottom "info bar" showing the channel and what's on now (or next).
struct ChannelBanner: View {
    private enum Layout {
        static let logoWidth: CGFloat = 360
        static let logoHeight: CGFloat = 110
        static let summaryLines = 2
        static let progressHeight: CGFloat = 8
    }

    let channel: Channel
    let program: ScheduledProgram?
    let isShowingNext: Bool

    @Environment(\.theme) private var theme

    var body: some View {
        TimelineView(.periodic(from: .now, by: ScheduleConstants.secondsPerMinute)) { context in
            HStack(alignment: .center, spacing: DesignTokens.Spacing.lg) {
                ChannelBadge(number: channel.number, callSign: channel.callSign, size: .large)
                Divider().overlay(theme.textSecondary.opacity(DesignTokens.Opacity.muted))
                if let program {
                    details(program, now: context.date)
                } else {
                    Text(channel.name).font(Typography.headline).foregroundStyle(theme.textPrimary)
                }
                Spacer(minLength: DesignTokens.Spacing.md)
                if let program {
                    logo(for: program)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .panel()
            .background(theme.scrim, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.large))
        }
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
                if !isShowingNext {
                    ProgressTrack(progress: program.progress(at: now), height: Layout.progressHeight)
                    Text(ScheduleFormatting.remaining(in: program, at: now))
                        .font(Typography.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            RemoteHints()
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

/// A compact legend of remote controls.
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
