import SwiftUI

/// Half-hour time labels across the top of the grid.
struct GuideTimeRuler: View {
    let scale: GuideTimeScale

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: GuideLayout.cellSpacing) {
            Text(ScheduleFormatting.day(scale.window.start).uppercased())
                .font(Typography.micro)
                .foregroundStyle(theme.textSecondary)
                .frame(width: GuideLayout.channelColumnWidth, alignment: .leading)
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
