import Foundation
import RetroGuideKit

/// Keeps the viewer's audio and subtitle rules in sync across their devices
/// through iCloud's key-value store. Without iCloud it simply keeps nothing,
/// and the device's own copy (``PreferencesStore``) is used.
@MainActor
final class CloudTrackRulesStore {
    private enum Key {
        static let trackRules = "trackRules.v1"
    }

    /// Called when another device changed the rules.
    var onChange: ((TrackRules) -> Void)?

    private let store = NSUbiquitousKeyValueStore.default
    /// Lives as long as the app model that owns this store (the app's
    /// lifetime); the handler holds it weakly.
    private var observer: NSObjectProtocol?

    func start() {
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] notification in
            let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            MainActor.assumeIsolated {
                guard changedKeys.contains(Key.trackRules), let self, let rules = self.rules else { return }
                self.onChange?(rules)
            }
        }
        store.synchronize()
    }

    var rules: TrackRules? {
        store.data(forKey: Key.trackRules).flatMap { try? JSONDecoder().decode(TrackRules.self, from: $0) }
    }

    func save(_ rules: TrackRules) {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        store.set(data, forKey: Key.trackRules)
    }
}
