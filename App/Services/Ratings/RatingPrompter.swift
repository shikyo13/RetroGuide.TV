#if os(iOS)
import Foundation
import RetroGuideKit

/// Keeps count of watching time for ``RatingPromptPacing`` and says when to
/// ask for an App Store rating.
@MainActor
final class RatingPrompter {
    private enum Key {
        static let pacing = "ratings.pacing.v1"
        /// Set once the viewer chose to rate from Settings.
        static let choseToRate = "ratings.choseToRate.v1"
    }

    private enum Timing {
        /// No request this soon after launch: the viewer has only just arrived.
        static let settleTime: TimeInterval = 2 * ScheduleConstants.secondsPerMinute
    }

    private var pacing: RatingPromptPacing
    private let defaults: UserDefaults
    private let createdAt = Date.now

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Key.pacing).flatMap { try? JSONDecoder().decode(RatingPromptPacing.self, from: $0) }
        self.pacing = stored ?? RatingPromptPacing()
    }

    var isRequestDue: Bool {
        !defaults.bool(forKey: Key.choseToRate)
            && Date.now.timeIntervalSince(createdAt) >= Timing.settleTime
            && pacing.isRequestDue(version: AppIdentity.version)
    }

    func recordWatching(_ duration: TimeInterval) {
        pacing.recordWatching(duration)
        save()
    }

    func requested() {
        pacing.requested(version: AppIdentity.version)
        save()
    }

    /// The viewer went to rate by choice: never ask again.
    static func choseToRate(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: Key.choseToRate)
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(pacing), forKey: Key.pacing)
    }
}
#endif
