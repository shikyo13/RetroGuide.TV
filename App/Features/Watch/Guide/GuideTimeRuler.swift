import SwiftUI

/// Half-hour time labels across the top of the grid. The channel column shows
/// the day, or other content such as time controls.
struct GuideTimeRuler<Leading: View>: View {
    let scale: GuideTimeScale
    @ViewBuilder let leading: () -> Leading

    @Environment(\.theme) private var theme
    @Environment(\.guideChannelColumnWidth) private var channelColumnWidth

    var body: some View {
        HStack(spacing: GuideLayout.cellSpacing) {
            leading()
                .frame(width: channelColumnWidth, alignment: .leading)
            ZStack(alignment: .leading) {
                ForEach(slotStarts, id: \.self) { start in
                    Text(ScheduleFormatting.time(start))
                        .font(Typography.clock)
                        .foregroundStyle(theme.textPrimary)
                        .padding(.leading, DesignTokens.Spacing.xs)
                        .frame(width: scale.width(from: start, to: start.addingTimeInterval(GuideLayout.Time.slot)), alignment: .leading)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(theme.textSecondary.opacity(DesignTokens.Opacity.muted))
                                .frame(width: DesignTokens.Stroke.thin)
                        }
                        .offset(x: scale.x(for: start))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: GuideLayout.rulerHeight)
    }

    private var slotStarts: [Date] {
        stride(from: .zero, to: scale.window.duration, by: GuideLayout.Time.slot).map {
            scale.window.start.addingTimeInterval($0)
        }
    }
}

extension GuideTimeRuler where Leading == GuideDayLabel {
    init(scale: GuideTimeScale) {
        self.init(scale: scale) { GuideDayLabel(date: scale.window.start) }
    }
}

/// The day shown above the channel column.
struct GuideDayLabel: View {
    let date: Date

    @Environment(\.theme) private var theme

    var body: some View {
        Text(ScheduleFormatting.day(date).uppercased())
            .font(Typography.micro)
            .foregroundStyle(theme.textSecondary)
    }
}
