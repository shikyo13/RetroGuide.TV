import RetroGuideKit
import SwiftUI

/// One row: Off, a number of minutes or the end of this program. Once set,
/// it shows when playback stops.
struct SleepTimerControl: View {
    private enum ChoiceID {
        static let off = "sleep.off"
        static let current = "sleep.current"
        static let endOfProgram = "sleep.endOfProgram"
    }

    @Environment(AppModel.self) private var app

    var body: some View {
        OptionMenu(
            title: String(localized: "Sleep timer"),
            systemImage: "moon",
            choices: choices,
            selection: Binding(
                get: { app.sleepTimer.deadline == nil ? ChoiceID.off : ChoiceID.current },
                set: { select($0) }
            )
        )
    }

    private var choices: [OptionMenu.Choice] {
        var choices = [OptionMenu.Choice(id: ChoiceID.off, title: String(localized: "Off", comment: "Sleep timer turned off"))]
        if let deadline = app.sleepTimer.deadline {
            choices.append(.init(id: ChoiceID.current, title: String(localized: "Playback stops at \(deadline.formatted(date: .omitted, time: .shortened))")))
        }
        choices += SleepDeadline.presets.map { .init(id: String($0), title: String(localized: "\($0) minutes")) }
        if !app.tuner.isWatchingFromBeginning, SleepDeadline.endOfProgram(app.tuner.program) != nil {
            choices.append(.init(id: ChoiceID.endOfProgram, title: String(localized: "End of this program")))
        }
        return choices
    }

    private func select(_ id: String) {
        switch id {
        case ChoiceID.off: app.sleepTimer.cancel()
        case ChoiceID.current: break
        case ChoiceID.endOfProgram:
            if let end = SleepDeadline.endOfProgram(app.tuner.program) { app.sleepTimer.start(until: end) }
        default:
            if let minutes = Int(id) { app.sleepTimer.start(until: SleepDeadline.duration(minutes: minutes)) }
        }
    }
}
