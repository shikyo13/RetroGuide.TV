import Foundation
import RetroGuideKit

/// Adds up today's playing time and says which ``UsageEvent/WatchTime``
/// thresholds it crossed. Saved so a relaunch keeps the day's total.
@MainActor
final class WatchTimeCounter {
    private enum Keys {
        static let tally = "usage.watchTimeTally"
    }

    private let defaults: UserDefaults
    private var tally: WatchTimeTally
    private var playingSince: Date?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        tally = defaults.data(forKey: Keys.tally).flatMap { try? JSONDecoder().decode(WatchTimeTally.self, from: $0) }
            ?? WatchTimeTally()
    }

    /// Starts or stops the clock; returns the thresholds the time so far crossed.
    func playing(_ isPlaying: Bool, now: Date = .now) -> [UsageEvent.WatchTime] {
        let crossed = flush(now: now)
        playingSince = isPlaying ? now : nil
        return crossed
    }

    /// Counts the time played so far without stopping the clock (a periodic check,
    /// so time isn't lost if the app is closed while playing).
    func flush(now: Date = .now) -> [UsageEvent.WatchTime] {
        guard let since = playingSince else { return [] }
        playingSince = now
        let crossed = tally.add(now.timeIntervalSince(since), at: now)
        if let data = try? JSONEncoder().encode(tally) { defaults.set(data, forKey: Keys.tally) }
        return crossed
    }
}
