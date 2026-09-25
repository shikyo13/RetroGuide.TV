import RetroGuideKit
import SwiftUI

/// Time ruler plus the visible channel rows, with a "now" line across them.
struct GuideGridView: View {
    let model: GuideModel
    let tunedChannelID: String?
    let showsFocus: Bool

    @Environment(\.guideChannelColumnWidth) private var channelColumnWidth

    var body: some View {
        TimelineView(.periodic(from: .now, by: ScheduleConstants.secondsPerMinute)) { context in
            GeometryReader { proxy in
                let scale = GuideTimeScale(
                    window: model.window,
                    width: proxy.size.width - channelColumnWidth - GuideLayout.cellSpacing
                )
                VStack(alignment: .leading, spacing: GuideLayout.rowSpacing) {
                    GuideTimeRuler(scale: scale)
                    rows(scale: scale, now: context.date)
                }
                .overlay(alignment: .topLeading) {
                    NowLine(scale: scale, now: context.date)
                }
            }
        }
        .frame(height: GuideLayout.rulerHeight + GuideLayout.rowSpacing + GuideLayout.gridHeight)
    }

    private func rows(scale: GuideTimeScale, now: Date) -> some View {
        VStack(spacing: GuideLayout.rowSpacing) {
            ForEach(model.visibleRows, id: \.self) { row in
                let channel = model.channels[row]
                GuideRowView(
                    channel: channel,
                    scale: scale,
                    now: now,
                    focusedProgramID: row == model.focusedRow && showsFocus ? model.focusedProgram?.id : nil,
                    isTuned: channel.id == tunedChannelID
                )
            }
        }
        .frame(height: GuideLayout.gridHeight, alignment: .top)
    }
}

/// Converts between guide time and horizontal position.
struct GuideTimeScale {
    let window: DateInterval
    let width: CGFloat

    var pointsPerSecond: CGFloat {
        width / window.duration
    }

    /// X offset (from the start of the timeline area) of `date`, clamped to the window.
    func x(for date: Date) -> CGFloat {
        let clamped = min(max(date, window.start), window.end)
        return clamped.timeIntervalSince(window.start) * pointsPerSecond
    }

    func width(from start: Date, to end: Date) -> CGFloat {
        max(x(for: end) - x(for: start), .zero)
    }
}

/// The vertical line marking the current time.
struct NowLine: View {
    let scale: GuideTimeScale
    let now: Date

    @Environment(\.theme) private var theme
    @Environment(\.guideChannelColumnWidth) private var channelColumnWidth

    var body: some View {
        if scale.window.contains(now) {
            Rectangle()
                .fill(theme.nowLine)
                .frame(width: GuideLayout.nowLineWidth)
                .offset(x: channelColumnWidth + GuideLayout.cellSpacing + scale.x(for: now))
                .allowsHitTesting(false)
        }
    }
}
