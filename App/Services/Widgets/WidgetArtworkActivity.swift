import UIKit

/// Gives an in-progress cache fill time to finish when the viewer returns Home.
@MainActor
final class WidgetArtworkActivity {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    init(onExpiration: @escaping @MainActor @Sendable () -> Void) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Widget artwork") { [weak self] in
            onExpiration()
            self?.end()
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
