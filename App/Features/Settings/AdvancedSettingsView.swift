import RetroGuideKit
import SwiftUI

/// Settings most people never need: the player, scheduler tuning, one order
/// for every channel, and titles removed from channels.
struct AdvancedSettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        SettingsPage(title: String(localized: "Advanced")) {
            SettingsSection(String(localized: "Playback")) {
                NavigationLink { PlayerEnginePickerView() } label: {
                    SettingsRowLabel(title: String(localized: "Player"), systemImage: "play.rectangle", value: app.preferences.playerEngine.displayName)
                }
            }
            SettingsSection(String(localized: "Scheduling")) {
                if !app.parentalControls.policy.isEnabled || !app.parentalControls.policy.usesCustomLineup {
                    NavigationLink { SimulcastLimitPickerView() } label: {
                        SettingsRowLabel(title: String(localized: "Channels per show"), systemImage: "rectangle.stack", value: app.customization.simulcastLimit.displayName)
                    }
                }
                if app.pro.access.canChangeScheduling {
                    NavigationLink { ScheduleGridPickerView() } label: {
                        SettingsRowLabel(title: String(localized: "Program start times"), systemImage: "clock", value: app.preferences.scheduleGrid.displayName)
                    }
                    NavigationLink { AllChannelsOrderView() } label: {
                        SettingsRowLabel(title: String(localized: "Schedule order for all channels"), systemImage: "shuffle",
                                         value: AllChannelsOrdering.summary(app.customization.defaultOrdering))
                    }
                } else {
                    ProLockedRow(title: String(localized: "Program start times"), systemImage: "clock").proEntry(.schedule)
                    ProLockedRow(title: String(localized: "Schedule order for all channels"), systemImage: "shuffle").proEntry(.schedule)
                }
                if removedTitleCount > .zero {
                    NavigationLink { RemovedTitlesPage() } label: {
                        SettingsRowLabel(title: String(localized: "Removed from channels"), systemImage: "minus.circle", value: removedTitleCount.formatted())
                    }
                }
            }
        }
    }

    /// Shows and movies removed from channels by hand, across every channel.
    private var removedTitleCount: Int {
        app.customization.removedTitles.values.reduce(.zero) { $0 + $1.count }
    }
}
