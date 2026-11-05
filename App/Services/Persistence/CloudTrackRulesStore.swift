import Foundation
import RetroGuideKit

/// Reads the previous key-value store once when upgrading to settings sync.
/// New cloud writes are controlled by the iCloud Sync preference.
@MainActor
final class CloudTrackRulesStore {
    private enum Key { static let trackRules = "trackRules.v1" }
    private let store = NSUbiquitousKeyValueStore.default

    var rules: TrackRules? {
        store.data(forKey: Key.trackRules).flatMap { try? JSONDecoder().decode(TrackRules.self, from: $0) }
    }
}
