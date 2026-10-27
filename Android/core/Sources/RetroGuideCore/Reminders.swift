import Foundation
import RetroGuideKit

struct ReminderInfo: Encodable, Sendable {
    let id: String
    let channelID: String
    let title: String
    let channelName: String
    let start: Date

    init(_ reminder: ProgramReminder) {
        id = reminder.id
        channelID = reminder.channelID
        title = reminder.title
        channelName = reminder.channelName
        start = reminder.start
    }
}

/// Upcoming reminders, and why something changed (a limit, a moved airing).
struct RemindersState: Encodable, Sendable {
    let pending: [ReminderInfo]
    let message: String?
    /// The reminder that just came due (started within the last few minutes).
    let due: ReminderInfo?
}

struct ReminderParams: Decodable, Sendable {
    let channelID: String
    let programID: String
}

struct ReminderIDParams: Decodable, Sendable {
    let id: String
}

extension CoreState {
    /// How far ahead a reminder's airing is looked for.
    private static let reminderHorizon: TimeInterval = 2 * 24 * ScheduleConstants.secondsPerHour

    /// The reminders, with `message` or else a note left by a lineup change (shown once).
    func remindersState(message: String? = nil, due: ProgramReminder? = nil) -> RemindersState {
        let note = message ?? reminderNote
        reminderNote = nil
        return RemindersState(pending: reminders.map(ReminderInfo.init), message: note, due: due.map(ReminderInfo.init))
    }

    /// Adds a reminder for an upcoming airing, or removes it if it's set (the guide's Remind me).
    func toggleReminder(_ params: ReminderParams) throws -> RemindersState {
        guard let channel = channel(withID: params.channelID) else { throw CoreError.unknownChannel }
        let now = Date.now
        guard let program = channel.timeline.programs(overlapping: DateInterval(start: now, duration: Self.reminderHorizon))
            .first(where: { $0.id == params.programID })
        else { throw CoreError.nothingScheduled }
        let reminder = ProgramReminder(channel: channel, program: program)
        if reminders.contains(where: { $0.id == reminder.id }) {
            reminders.removeAll { $0.id == reminder.id }
            saveReminders()
            return remindersState()
        }
        guard isPro else { return remindersState() }
        guard reminder.start > now else { return remindersState(message: "This program has already started.") }
        guard reminders.count < ProgramReminder.Limits.pending else {
            return remindersState(message: "You can keep up to \(ProgramReminder.Limits.pending) upcoming reminders. Remove one first.")
        }
        reminders.append(reminder)
        reminders.sort { $0.start < $1.start }
        saveReminders()
        return remindersState()
    }

    func removeReminder(_ params: ReminderIDParams) -> RemindersState {
        reminders.removeAll { $0.id == params.id }
        saveReminders()
        return remindersState()
    }

    /// Takes reminders whose programs have started off the list; the latest one
    /// (if it started only moments ago) is due.
    func checkReminders() -> RemindersState {
        let now = Date.now
        let fired = reminders.filter { $0.start <= now }
        guard !fired.isEmpty else { return remindersState() }
        reminders.removeAll { $0.start <= now }
        saveReminders()
        let due = fired.last.flatMap { now.timeIntervalSince($0.start) < ProgramReminder.Limits.staleAfter ? $0 : nil }
        return remindersState(due: due)
    }

    /// After the lineup changes: drop reminders whose airing moved, and ones parental controls no longer allow.
    func reconcileReminders() -> String? {
        let now = Date.now
        let invalid = reminders.filter { reminder in
            guard reminder.start > now else { return false }
            if parentalPolicy.isEnabled, !parentalAllowedItemIDs.contains(reminder.itemID) { return true }
            guard let channel = channels.first(where: { $0.isIdentified(by: reminder.channelID) }),
                  let program = channel.timeline.program(at: reminder.start) else { return true }
            return program.item.id != reminder.itemID || program.start != reminder.start
        }
        guard !invalid.isEmpty else { return nil }
        reminders.removeAll { reminder in invalid.contains { $0.id == reminder.id } }
        saveReminders()
        return "\(invalid.count) reminder(s) were removed because their scheduled programs changed."
    }

    private func saveReminders() {
        store?.save(reminders, file: CoreStore.File.reminders)
    }
}
