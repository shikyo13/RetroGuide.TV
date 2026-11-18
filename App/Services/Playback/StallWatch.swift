import RetroGuideKit

/// Notices when a playing program stops to buffer for longer than a viewer
/// would shrug off, so it can be counted (once a day at most, by the usage
/// ledger). Short hiccups the player recovers from aren't reported.
@MainActor
final class StallWatch {
    private enum Timing {
        /// Buffering at least this long counts as a stall.
        static let threshold: Duration = .seconds(5)
    }

    /// Called when a stall passes ``Timing/threshold``.
    var onStalled: ((UsageEvent.Location) -> Void)?

    private var pending: Task<Void, Never>?

    /// The player started (`true`) or stopped (`false`) buffering a stream
    /// that was already playing.
    func buffering(_ isBuffering: Bool, location: UsageEvent.Location) {
        guard isBuffering else { reset(); return }
        guard pending == nil else { return }
        pending = Task { [weak self] in
            try? await Task.sleep(for: Timing.threshold)
            guard !Task.isCancelled, let self else { return }
            pending = nil
            onStalled?(location)
        }
    }

    /// The stream played on, stopped or changed.
    func reset() {
        pending?.cancel()
        pending = nil
    }
}
