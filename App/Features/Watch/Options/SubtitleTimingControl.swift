import RetroGuideKit
import SwiftUI

/// Moves subtitles earlier or later for what's on now, for subtitle files
/// timed for another release. A slider with fine −/+ steps on iPhone and
/// iPad; on Apple TV, Left and Right on the remote, faster while held.
struct SubtitleTimingControl: View {
    let tuner: Tuner

    @Environment(\.theme) private var theme

    private var delay: TimeInterval { tuner.subtitleDelay }

    private var caption: String {
        let how = "Move subtitles later if they appear before speech, or earlier if they appear after it."
        return tuner.program?.item.series == nil
            ? "\(how) Applies to this subtitle track while watching this program."
            : "\(how) The next episodes of this show start with the same timing."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            #if os(tvOS)
            RemoteAdjuster(tuner: tuner)
            #else
            SettingsRowLabel(
                title: "Subtitle timing",
                systemImage: "clock.arrow.2.circlepath",
                value: SubtitleTiming.description(of: delay),
                accessory: nil
            )
            .font(Typography.settingsBody)
            touchControls
            #endif
            Text(caption)
                .font(Typography.settingsCaption)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    #if !os(tvOS)
    private var touchControls: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            // No `step:`: iOS draws a tick per step. The tuner rounds to the fine step.
            Slider(
                value: Binding(get: { delay }, set: { tuner.setSubtitleDelay($0) }),
                in: SubtitleTiming.range
            ) {
                Text("Subtitle timing")
            } minimumValueLabel: {
                Text("Earlier").secondaryText()
            } maximumValueLabel: {
                Text("Later").secondaryText()
            }
            .tint(theme.accent)
            .accessibilityValue(SubtitleTiming.description(of: delay))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: tuner.setSubtitleDelay(delay + SubtitleTiming.fineStep)
                case .decrement: tuner.setSubtitleDelay(delay - SubtitleTiming.fineStep)
                @unknown default: break
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DesignTokens.Spacing.sm) { adjustmentButtons }
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) { adjustmentButtons }
            }
        }
    }

    @ViewBuilder
    private var adjustmentButtons: some View {
        stepButton(systemImage: "minus", label: "Earlier", by: -SubtitleTiming.fineStep)
            .disabled(delay <= SubtitleTiming.range.lowerBound)
        stepButton(systemImage: "plus", label: "Later", by: SubtitleTiming.fineStep)
            .disabled(delay >= SubtitleTiming.range.upperBound)
        Button("Reset") { tuner.setSubtitleDelay(.zero) }
            .buttonStyle(.retro)
            .disabled(delay == .zero)
            .accessibilityHint("Restores this track's original timing.")
    }

    private func stepButton(systemImage: String, label: String, by step: TimeInterval) -> some View {
        Button {
            tuner.setSubtitleDelay(delay + step)
        } label: {
            Label(label, systemImage: systemImage)
        }
        .buttonStyle(.retro)
        .accessibilityLabel("\(label) by \(SubtitleTiming.fineStep.formatted()) seconds")
    }
    #endif
}

#if os(tvOS)
/// A row the remote's Left and Right move through; Select restores the original timing.
private struct RemoteAdjuster: View {
    private enum Timing {
        /// Presses closer together than this count as holding the button.
        static let repeatWindow: TimeInterval = 0.35
    }

    let tuner: Tuner

    @State private var repeatCount = 0
    @State private var lastPress = Date.distantPast
    @State private var lastDirection: MoveCommandDirection?
    @FocusState private var isFocused: Bool

    var body: some View {
        Button {
            tuner.setSubtitleDelay(.zero)
        } label: {
            SettingsRowLabel(
                title: "Subtitle timing",
                systemImage: "clock.arrow.2.circlepath",
                value: isFocused
                    ? "◀ \(SubtitleTiming.description(of: tuner.subtitleDelay)) ▶"
                    : SubtitleTiming.description(of: tuner.subtitleDelay),
                accessory: nil
            )
        }
        .buttonStyle(.retroRow)
        .focused($isFocused)
        .onMoveCommand(perform: move)
        .accessibilityValue(SubtitleTiming.description(of: tuner.subtitleDelay))
        .accessibilityHint("Left and Right move subtitles earlier or later. Select restores the original timing.")
    }

    private func move(_ direction: MoveCommandDirection) {
        let sign: TimeInterval
        switch direction {
        case .left: sign = -1
        case .right: sign = 1
        default: return
        }
        let now = Date.now
        let isHeld = direction == lastDirection && now.timeIntervalSince(lastPress) < Timing.repeatWindow
        repeatCount = isHeld ? repeatCount + 1 : .zero
        lastPress = now
        lastDirection = direction
        tuner.setSubtitleDelay(tuner.subtitleDelay + sign * SubtitleTiming.step(forRepeat: repeatCount))
    }
}
#endif
