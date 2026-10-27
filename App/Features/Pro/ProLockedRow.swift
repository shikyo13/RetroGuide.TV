import SwiftUI

/// A settings row for a Pro feature the viewer doesn't have yet: it opens
/// the upgrade page instead of the feature.
struct ProLockedRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        NavigationLink {
            ProUpgradeView()
        } label: {
            SettingsRowLabel(title: title, systemImage: systemImage, value: ProLockedRow.badge, accessory: "lock.fill")
        }
    }

    static let badge = "Pro"
}
