import RetroTVKit
import SwiftUI

/// One channel row: the channel cell followed by its programs in the visible window.
struct GuideRowView: View {
    let channel: Channel
    let scale: GuideTimeScale
    let now: Date
    let focusedProgramID: String?
    let isTuned: Bool

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: GuideLayout.cellSpacing) {
            channelCell
            ZStack(alignment: .leading) {
                ForEach(channel.timeline.programs(overlapping: scale.window)) { program in
                    GuideProgramCell(
                        program: program,
                        scale: scale,
                        now: now,
                        isFocused: program.id == focusedProgramID
                    )
                    .offset(x: scale.x(for: program.start))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .frame(height: GuideLayout.rowHeight)
    }

    private var channelCell: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            ChannelBadge(number: channel.number, callSign: channel.callSign)
            Text(channel.name)
                .font(Typography.caption)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(Typography.minimumScaleFactor)
            Spacer(minLength: .zero)
        }
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .frame(width: GuideLayout.channelColumnWidth, height: GuideLayout.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                .fill(isTuned ? theme.surfaceRaised : theme.surface.opacity(DesignTokens.Opacity.strong))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                .strokeBorder(isTuned ? theme.accent : .clear, lineWidth: DesignTokens.Stroke.thin)
        )
    }
}
