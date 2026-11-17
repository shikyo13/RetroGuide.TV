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
                    tick(at: start)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .frame(height: GuideLayout.rulerHeight)
    }

    /// A time label at its half-hour mark. Near the right edge the label
    /// sits before the mark, so it is never cut off.
    private func tick(at start: Date) -> some View {
        let x = scale.x(for: start)
        let fitsAfter = scale.width - x >= GuideLayout.rulerLabelWidth
        let width = fitsAfter ? scale.width(from: start, to: start.addingTimeInterval(GuideLayout.Time.slot)) : GuideLayout.rulerLabelWidth
        return Text(ScheduleFormatting.time(start))
            .font(Typography.clock)
            .foregroundStyle(theme.textPrimary)
            // Some locales' times are wider ("오후 8:00"): shrink rather than cut off.
            .lineLimit(1)
            .minimumScaleFactor(Typography.minimumScaleFactor)
            .padding(fitsAfter ? .leading : .trailing, DesignTokens.Spacing.xs)
            .frame(width: width, alignment: fitsAfter ? .leading : .trailing)
            .overlay(alignment: fitsAfter ? .leading : .trailing) {
                Rectangle()
                    .fill(theme.textSecondary.opacity(DesignTokens.Opacity.muted))
                    .frame(width: DesignTokens.Stroke.thin)
            }
            .offset(x: fitsAfter ? x : x - width)
    }

    /// The half-hour marks inside the window. A window that follows the
    /// clock (iPhone in portrait) starts between marks; its start is not a
    /// time worth labelling.
    private var slotStarts: [Date] {
        let floor = GuideLayout.slotStart(containing: scale.window.start)
        let first = floor < scale.window.start ? floor.addingTimeInterval(GuideLayout.Time.slot) : floor
        return stride(from: first.timeIntervalSince(scale.window.start), to: scale.window.duration, by: GuideLayout.Time.slot).map {
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
