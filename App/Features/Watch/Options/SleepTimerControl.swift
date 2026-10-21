import RetroGuideKit
import SwiftUI

struct SleepTimerControl: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var minutes = 45
    @State private var enteredMinutes = "45"
    @FocusState private var isEditingMinutes: Bool

    private var customMinutes: Int? {
        #if os(iOS)
        Int(enteredMinutes.trimmingCharacters(in: .whitespacesAndNewlines))
        #else
        minutes
        #endif
    }

    var body: some View {
        SettingsSection("Sleep timer") {
            if let deadline = app.sleepTimer.deadline {
                Text("Playback stops at \(deadline.formatted(date: .omitted, time: .shortened))")
                    .font(Typography.settingsBody).foregroundStyle(theme.accent)
                Button("Cancel sleep timer", systemImage: "moon.zzz") { app.sleepTimer.cancel() }
            }
            OptionMenu(title: "Stop after", systemImage: "moon", choices: SleepDeadline.presets.map {
                .init(id: String($0), title: "\($0) minutes")
            }, selection: Binding(get: { "" }, set: { value in
                if let minutes = Int(value) { app.sleepTimer.start(until: SleepDeadline.duration(minutes: minutes)) }
            }))
            #if os(tvOS)
            let customLayout = AnyLayout(VStackLayout(alignment: .leading, spacing: DesignTokens.Spacing.sm))
            #else
            let customLayout = textSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: DesignTokens.Spacing.sm))
                : AnyLayout(HStackLayout(spacing: DesignTokens.Spacing.sm))
            #endif
            customLayout {
                #if os(iOS)
                TextField("Minutes", text: $enteredMinutes)
                    .keyboardType(.numberPad)
                    .font(Typography.settingsBody)
                    .focused($isEditingMinutes)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .frame(minHeight: DesignTokens.Control.minimumHeight)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.medium))
                    .accessibilityLabel("Custom timer minutes")
                Text("minutes").font(Typography.settingsBody)
                #else
                NumberControl(title: "\(minutes) minutes", value: $minutes, range: SleepDeadline.customRange)
                #endif
                Button("Set timer") {
                    guard let minutes = customMinutes, SleepDeadline.customRange.contains(minutes) else { return }
                    isEditingMinutes = false
                    app.sleepTimer.start(until: SleepDeadline.duration(minutes: minutes))
                }
                    .disabled(customMinutes.map { !SleepDeadline.customRange.contains($0) } ?? true)
            }
            if customMinutes.map({ !SleepDeadline.customRange.contains($0) }) ?? true {
                Text("Enter \(SleepDeadline.customRange.lowerBound)–\(SleepDeadline.customRange.upperBound) minutes.")
                    .font(Typography.settingsCaption).foregroundStyle(theme.textSecondary)
            }
            Button("End of this program", systemImage: "stop.circle") {
                if let end = SleepDeadline.endOfProgram(app.tuner.program) { app.sleepTimer.start(until: end) }
            }
            .disabled(SleepDeadline.endOfProgram(app.tuner.program) == nil)
            Text("Stops video, audio and Picture in Picture. Changing channels keeps the chosen stop time.")
                .font(Typography.settingsCaption).foregroundStyle(theme.textSecondary)
        }
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isEditingMinutes = false }
                    .accessibilityLabel("Done entering minutes")
            }
        }
        #endif
    }
}
