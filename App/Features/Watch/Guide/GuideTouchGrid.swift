#if os(iOS)
import RetroGuideKit
import SwiftUI

/// The guide grid on iPhone and iPad: every channel in a vertical scroll, a tap
/// to select a program (and a second tap to watch), and time controls or a
/// sideways swipe to move through the schedule.
struct GuideTouchGrid: View {
    let model: GuideModel
    let tunedChannelID: String?
    let onTune: (Channel) -> Void

    @Environment(\.guideChannelColumnWidth) private var channelColumnWidth

    var body: some View {
        TimelineView(.periodic(from: .now, by: ScheduleConstants.secondsPerMinute)) { context in
            GeometryReader { proxy in
                let scale = GuideTimeScale(
                    window: model.window,
                    width: proxy.size.width - channelColumnWidth - GuideLayout.cellSpacing
                )
                VStack(alignment: .leading, spacing: GuideLayout.rowSpacing) {
                    GuideTimeRuler(scale: scale) {
                        GuideTimeControls(model: model)
                    }
                    rows(scale: scale, now: context.date)
                        .overlay(alignment: .topLeading) {
                            NowLine(scale: scale, now: context.date)
                        }
                }
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: TouchGesture.minimumDistance)
                .onEnded { value in
                    switch SwipeDirection(translation: value.translation) {
                    case .left: model.shiftWindow(bySlots: 1)
                    case .right: model.shiftWindow(bySlots: -1)
                    case .up, .down, nil: break
                    }
                }
        )
    }

    private func rows(scale: GuideTimeScale, now: Date) -> some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(spacing: GuideLayout.rowSpacing) {
                    ForEach(model.channels.indices, id: \.self) { row in
                        let channel = model.channels[row]
                        GuideRowView(
                            channel: channel,
                            scale: scale,
                            now: now,
                            focusedProgramID: row == model.focusedRow ? model.focusedProgram?.id : nil,
                            isTuned: channel.id == tunedChannelID,
                            onSelectChannel: { onTune(channel) },
                            onSelectProgram: { program in select(program, row: row) }
                        )
                        .id(row)
                    }
                }
            }
            .onAppear { reader.scrollTo(model.focusedRow, anchor: .center) }
        }
    }

    /// The first tap selects a program; tapping the selected one tunes its channel.
    private func select(_ program: ScheduledProgram, row: Int) {
        if row == model.focusedRow, program.id == model.focusedProgram?.id {
            onTune(model.channels[row])
        } else {
            model.select(row: row, program: program)
        }
    }
}

/// Earlier, now and later buttons above the channel column.
private struct GuideTimeControls: View {
    let model: GuideModel

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: .zero) {
            control("Earlier", systemImage: "chevron.left", isEnabled: !model.isShowingNow) {
                model.shiftWindow(bySlots: -1)
            }
            control("Now", systemImage: "clock.arrow.circlepath", isEnabled: !model.isShowingNow) {
                model.jumpToNow()
            }
            control("Later", systemImage: "chevron.right", isEnabled: true) {
                model.shiftWindow(bySlots: 1)
            }
        }
        .font(Typography.bodyEmphasis)
    }

    private func control(_ title: String, systemImage: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(isEnabled ? theme.accent : theme.textSecondary.opacity(DesignTokens.Opacity.muted))
        .disabled(!isEnabled)
    }
}
#endif
