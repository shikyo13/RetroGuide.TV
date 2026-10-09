import RetroGuideKit
import SwiftUI

/// Moves subtitles earlier or later for what's on now, for subtitle files
/// timed for another release. A slider with fine −/+ steps on iPhone and
/// iPad; on Apple TV, Left and Right on the remote, faster while held.
struct SubtitleTimingControl: View {
    let tuner: Tuner

    @Environment(\.theme) private var theme

    private var delay: TimeInterval { tuner.subtitleDelay }

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
            touchControls
            #endif
        }
    }

    #if !os(tvOS)
    private var touchControls: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            stepButton(systemImage: "minus", label: "Earlier", by: -SubtitleTiming.fineStep)
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
            stepButton(systemImage: "plus", label: "Later", by: SubtitleTiming.fineStep)
            Button("Reset") { tuner.setSubtitleDelay(.zero) }
                .buttonStyle(.retro)
                .disabled(delay == .zero)
        }
    }

    private func stepButton(systemImage: String, label: String, by step: TimeInterval) -> some View {
        Button {
            tuner.setSubtitleDelay(delay + step)
        } label: {
            Image(systemName: systemImage)
        }
        .buttonStyle(.retroIcon)
        .accessibilityLabel("\(label) by \(SubtitleTiming.fineStep.formatted()) seconds")
    }
    #endif
}

#if os(tvOS)
/// A row the remote's Left and Right move through; Select puts subtitles back in sync.
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
        .accessibilityHint("Left and Right move subtitles earlier or later. Select puts them back in sync.")
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
