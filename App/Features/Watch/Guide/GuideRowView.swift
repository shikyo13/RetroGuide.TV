import RetroGuideKit
import SwiftUI

/// One channel row: the channel cell followed by its programs in the visible window.
struct GuideRowView: View {
    let channel: Channel
    let scale: GuideTimeScale
    let now: Date
    let focusedProgramID: String?
    let isTuned: Bool
    /// Touch only: tapping the channel cell or a program.
    var onSelectChannel: (() -> Void)?
    var onSelectProgram: ((ScheduledProgram) -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.guideChannelColumnWidth) private var channelColumnWidth
    @Environment(\.isNarrowLayout) private var isNarrowLayout

    var body: some View {
        HStack(spacing: GuideLayout.cellSpacing) {
            channelCell
                .tapAction(onSelectChannel)
            ZStack(alignment: .leading) {
                ForEach(channel.timeline.programs(overlapping: scale.window)) { program in
                    GuideProgramCell(
                        program: program,
                        scale: scale,
                        now: now,
                        isFocused: program.id == focusedProgramID
                    )
                    .tapAction(onSelectProgram.map { select in { select(program) } })
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
            if !isNarrowLayout {
                Text(channel.name)
                    .font(Typography.caption)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(Typography.minimumScaleFactor)
            }
            Spacer(minLength: .zero)
        }
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .frame(width: channelColumnWidth, height: GuideLayout.rowHeight)
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
