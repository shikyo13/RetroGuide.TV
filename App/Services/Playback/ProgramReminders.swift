import Foundation
import Observation
import RetroGuideKit
#if os(iOS)
import UserNotifications
#endif

@MainActor @Observable
final class ProgramReminders: NSObject {
    private enum Storage { static let key = "programReminders.v1" }
    private(set) var pending: [ProgramReminder] = []
    var message: String?
    var due: ProgramReminder?
    @ObservationIgnored var onOpen: ((String) -> Void)?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var adding = false
    @ObservationIgnored private var generation = 0

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        if let data = defaults.data(forKey: Storage.key),
           let saved = try? JSONDecoder().decode([ProgramReminder].self, from: data) { pending = saved }
        #if os(iOS)
        UNUserNotificationCenter.current().delegate = self
        #endif
        arm()
    }

    func contains(_ reminder: ProgramReminder) -> Bool { pending.contains { $0.id == reminder.id } }

    func add(_ reminder: ProgramReminder, isPro: Bool) async {
        guard isPro, !adding, !contains(reminder) else { return }
        guard reminder.start > .now else { message = "This program has already started."; return }
        guard pending.count < ProgramReminder.Limits.pending else {
            message = "You can keep up to \(ProgramReminder.Limits.pending) upcoming reminders. Remove one first."
            return
        }
        let generation = generation
        adding = true
        defer { adding = false }
        #if os(iOS)
        do {
            let center = UNUserNotificationCenter.current()
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                message = "Notifications are off. Enable them for RetroGuide.TV in iPhone or iPad Settings to receive reminders."
                return
            }
            guard generation == self.generation else { return }
            guard reminder.start > .now else { message = "This program has already started."; return }
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = "Starting now on \(reminder.channelName)"
            content.sound = .default
            content.userInfo = ["channelID": reminder.channelID]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, reminder.start.timeIntervalSinceNow), repeats: false)
            try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
        } catch { message = "Couldn't set this reminder: \(error.localizedDescription)"; return }
        #endif
        guard generation == self.generation else {
            #if os(iOS)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminder.id])
            #endif
            return
        }
        pending.append(reminder)
        pending.sort { $0.start < $1.start }
        save()
        arm()
    }

    func remove(_ reminder: ProgramReminder) {
        pending.removeAll { $0.id == reminder.id }
        #if os(iOS)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminder.id])
        #endif
        save()
        arm()
    }

    func clear() {
        generation += 1
        #if os(iOS)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: pending.map(\.id))
        #endif
        pending = []
        due = nil
        timer?.cancel()
        save()
    }

    /// Drop an airing if a library or programming change moved it.
    func reconcile(channels: [Channel]) {
        let invalid = pending.filter { reminder in
            guard reminder.start > .now else { return false }
            guard let channel = channels.first(where: { $0.isIdentified(by: reminder.channelID) }),
                  let program = channel.timeline.program(at: reminder.start) else { return true }
            return program.item.id != reminder.itemID || program.start != reminder.start
        }
        for reminder in invalid { remove(reminder) }
        if !invalid.isEmpty { message = "\(invalid.count) reminder(s) were removed because their scheduled programs changed." }
    }

    func check(now: Date = .now) {
        let fired = pending.filter { $0.start <= now }
        if let recent = fired.last, now.timeIntervalSince(recent.start) < ProgramReminder.Limits.staleAfter { due = recent }
        pending.removeAll { $0.start <= now }
        save()
        arm()
    }

    func openNotification(identifier: String, channelID: String) {
        pending.removeAll { $0.id == identifier }
        if due?.id == identifier { due = nil }
        save()
        arm()
        onOpen?(channelID)
    }

    private func arm() {
        timer?.cancel()
        guard let first = pending.first else { return }
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(.zero, first.start.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.check()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(pending) { defaults.set(data, forKey: Storage.key) }
    }
}

#if os(iOS)
extension ProgramReminders: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in completionHandler([.banner, .sound]) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        let id = response.notification.request.content.userInfo["channelID"] as? String
        let identifier = response.notification.request.identifier
        Task { @MainActor in
            if let id { openNotification(identifier: identifier, channelID: id) }
            completionHandler()
        }
    }
}
#endif
