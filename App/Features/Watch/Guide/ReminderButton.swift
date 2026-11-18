import RetroGuideKit
import SwiftUI

struct ReminderButton: View {
    let channel: Channel
    let program: ScheduledProgram
    /// The main action where it sits (a search result that airs later).
    var isProminent = false
    @Environment(AppModel.self) private var app
    @State private var showsUpgrade = false

    var body: some View {
        let reminder = ProgramReminder(channel: channel, program: program)
        Button {
            if !app.pro.isPro { showsUpgrade = true }
            else if app.reminders.contains(reminder) { app.reminders.remove(reminder) }
            else { Task { await app.reminders.add(reminder, isPro: app.pro.isPro) } }
        } label: {
            Label(app.reminders.contains(reminder) ? "Cancel reminder" : "Remind me", systemImage: app.reminders.contains(reminder) ? "bell.fill" : "bell")
        }
        .buttonStyle(RetroButtonStyle(prominence: isProminent ? .primary : .secondary))
        .disabled(program.start <= .now)
        .sheet(isPresented: $showsUpgrade) { ProUpgradeView() }
    }
}
