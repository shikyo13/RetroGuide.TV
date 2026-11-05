import SwiftUI

struct CloudSyncSettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var confirmingLocalSetup = false
    @State private var confirmingRestore = false

    var body: some View {
        SettingsPage(title: "iCloud Sync") {
            CheckmarkRow(title: "Sync with iCloud", detail: "Use the same setup on devices signed into your Apple Account.",
                         isSelected: app.settingsSync.isEnabled) {
                if app.settingsSync.isEnabled { app.settingsSync.disable() }
                else { app.settingsSync.enable() }
            }
            if app.settingsSync.needsInitialChoice {
                SettingsSection("A setup is already in iCloud") {
                    CloudSyncExplanation("Choose which setup to use. A copy of this device’s current settings will be kept so you can restore it.")
                    Button { app.settingsSync.chooseInitialSetup(useLocal: false) } label: {
                        SettingsRowLabel(title: "Use iCloud setup", systemImage: "icloud.and.arrow.down", value: nil, accessory: nil)
                    }
                    Button { confirmingLocalSetup = true } label: {
                        SettingsRowLabel(title: "Use this device’s setup", systemImage: "icloud.and.arrow.up", value: nil, accessory: nil)
                    }
                }
            }
            if app.settingsSync.isEnabled {
                SettingsSection("Status") {
                    if app.settingsSync.isBusy { ProgressView("Syncing settings…") }
                    if let message = app.settingsSync.message {
                        Text(message).font(Typography.settingsBody).foregroundStyle(theme.textSecondary)
                    } else if app.settingsSync.hasPendingApplication {
                        CloudSyncExplanation("Settings are waiting for setup or a library refresh to finish. If parental settings are locked, unlock them to apply changes.")
                    } else if let date = app.settingsSync.lastSync {
                        CloudSyncExplanation("Last synced \(date.formatted(date: .abbreviated, time: .shortened))")
                    }
                    Button { app.settingsSync.applyLatest(); app.settingsSync.retry() } label: {
                        SettingsRowLabel(title: "Sync now", systemImage: "arrow.triangle.2.circlepath", value: nil, accessory: nil)
                    }.disabled(app.settingsSync.isBusy || app.settingsSync.needsInitialChoice)
                }
            } else if let message = app.settingsSync.message {
                Text(message).font(Typography.settingsBody).foregroundStyle(theme.textSecondary)
            }
            SettingsSection("Shared settings") {
                CloudSyncExplanation("Favorites, channels, scheduling, commercial settings, themes, audio and subtitle choices, library selections, and reminders.")
                NavigationLink { CloudSyncDetailsView() } label: {
                    SettingsRowLabel(title: "About iCloud Sync", systemImage: "info.circle", value: nil)
                }
            }
            if app.parentalSettingsFromCloud != nil {
                NavigationLink { ParentalControlsView() } label: {
                    SettingsRowLabel(title: "Parental Controls", systemImage: "lock.shield", value: "Review synced changes")
                }
                .buttonStyle(.retroRow)
            }
            CloudSyncExplanation("Connect your servers on each device. Parental restrictions and the parental lineup require review before they apply here.")
            if app.settingsSync.hasBackup {
                SettingsSection("Recovery") {
                    Button { confirmingRestore = true } label: {
                        SettingsRowLabel(title: "Restore this device’s previous setup", systemImage: "arrow.uturn.backward", value: nil, accessory: nil)
                    }
                }
            }
        }
        .task { app.settingsSync.applyLatest() }
        .confirmationDialog("Replace the iCloud setup?", isPresented: $confirmingLocalSetup) {
            Button("Use This Device’s Setup", role: .destructive) { app.settingsSync.chooseInitialSetup(useLocal: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This device’s shared settings will replace those in iCloud and update your other connected devices. Their parental restrictions still require review.")
        }
        .confirmationDialog("Restore the previous setup?", isPresented: $confirmingRestore) {
            Button("Restore Setup") { app.settingsSync.restoreBackup() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This restores the shared settings saved before this device joined iCloud Sync. If sync is on, the restored choices will also sync to your other devices. Parental restrictions remain unchanged until reviewed.")
        }
    }
}

private struct CloudSyncDetailsView: View {
    @Environment(\.theme) private var theme
    var body: some View {
        SettingsPage(title: "About iCloud Sync") {
            SettingsSection("Your configuration") {
                CloudSyncExplanation("Your shared choices are stored in your private iCloud account. All devices need the same Apple Account and iCloud enabled.")
                CloudSyncExplanation("Channel settings include custom channels, hidden channels, removed shows and movies, and schedule ordering. Media files and generated program guides are not uploaded.")
                CloudSyncExplanation("Connect to Plex or Jellyfin on each device. Server passwords and access tokens stay on the device. Settings for unavailable libraries are retained until you connect them.")
            }
            SettingsSection("Device preferences") {
                CloudSyncExplanation("Player, video quality, widget, Top Shelf, recent-channel, and current-playback preferences stay on each device.")
                CloudSyncExplanation("Parental restrictions and the curated parental lineup are available for review in Parental Controls. Save them there to apply them on this device. Sync never changes a PIN or turns the parental lock on or off.")
                CloudSyncExplanation("Reminders appear when the matching program is available. Notification permission is set separately on each device.")
            }
            SettingsSection("When offline") {
                CloudSyncExplanation("Changes are saved locally and sync when iCloud is available. Turning sync off keeps your current setup and leaves the iCloud copy in place.")
            }
        }
        .font(Typography.settingsBody).foregroundStyle(theme.textSecondary)
    }
}

private struct CloudSyncExplanation: View {
    let text: String
    @Environment(\.theme) private var theme
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(Typography.settingsBody)
            .foregroundStyle(theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
