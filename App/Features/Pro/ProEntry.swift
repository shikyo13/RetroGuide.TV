import RetroGuideKit
import SwiftUI

/// Where the Pro page was opened from, for ``UsageEvent/Name/proViewed``.
private struct ProEntryKey: EnvironmentKey {
    static let defaultValue = UsageEvent.ProEntry.other
}

extension EnvironmentValues {
    var proEntry: UsageEvent.ProEntry {
        get { self[ProEntryKey.self] }
        set { self[ProEntryKey.self] = newValue }
    }
}

extension View {
    /// Says where a Pro page (or a locked row leading to one) is opened from.
    func proEntry(_ entry: UsageEvent.ProEntry) -> some View {
        environment(\.proEntry, entry)
    }
}
