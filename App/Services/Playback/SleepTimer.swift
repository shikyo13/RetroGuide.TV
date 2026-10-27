import Foundation
import Observation
import OSLog

@MainActor @Observable
final class SleepTimer {
    @ObservationIgnored private let logger = Logger(subsystem: "com.adamhunt.retroguide", category: "sleep-timer")
    private(set) var deadline: Date?
    private(set) var didExpire = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored var onExpire: (() -> Void)?

    func start(until date: Date) {
        cancel()
        deadline = date
        logger.info("Sleep timer armed for \(date, privacy: .public)")
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(.zero, date.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.checkDeadline()
        }
    }

    func checkDeadline(now: Date = .now) {
        guard let deadline, deadline <= now else { return }
        cancel()
        didExpire = true
        logger.info("Sleep timer expired")
        onExpire?()
    }

    func cancel() {
        task?.cancel()
        task = nil
        deadline = nil
        didExpire = false
    }

    func resumeWatching() { didExpire = false }
}
