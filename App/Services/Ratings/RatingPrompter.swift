#if os(iOS)
import Foundation
import RetroGuideKit

/// Keeps count of watching time for ``RatingPromptPacing`` and says when to
/// ask for an App Store rating.
@MainActor
final class RatingPrompter {
    private enum Key {
        static let pacing = "ratings.pacing.v1"
    }

    private var pacing: RatingPromptPacing
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Key.pacing).flatMap { try? JSONDecoder().decode(RatingPromptPacing.self, from: $0) }
        self.pacing = stored ?? RatingPromptPacing()
    }

    var isRequestDue: Bool {
        pacing.isRequestDue(version: AppIdentity.version)
    }

    func recordWatching(_ duration: TimeInterval) {
        pacing.recordWatching(duration)
        save()
    }

    func requested() {
        pacing.requested(version: AppIdentity.version)
        save()
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(pacing), forKey: Key.pacing)
    }
}
#endif
