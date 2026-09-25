import RetroGuideKit
import SwiftUI

/// Settings home, layered over live TV (which shrinks to picture-in-picture).
struct SettingsView: View {
    let onClose: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var isConfirmingSignOut = false

    var body: some View {
        NavigationStack {
            SettingsPage(title: "Settings", onExit: onClose) {
                SettingsSection("Picture") {
                    NavigationLink {
                        ThemePickerView()
                    } label: {
                        SettingsRowLabel(title: "Theme", systemImage: "paintpalette", value: app.theme.name)
                    }
                    Button {
                        app.preferences.showsScanlines.toggle()
                    } label: {
                        SettingsRowLabel(
                            title: "Scanlines on menus",
                            systemImage: "tv",
                            value: app.preferences.showsScanlines ? "On" : "Off",
                            accessory: nil
                        )
                    }
                }
                SettingsSection("Playback") {
                    NavigationLink {
                        PlayerEnginePickerView()
                    } label: {
                        SettingsRowLabel(title: "Player", systemImage: "play.rectangle", value: app.preferences.playerEngine.displayName)
                    }
                    #if os(tvOS)
                    NavigationLink {
                        DisplayMatchingPickerView()
                    } label: {
                        SettingsRowLabel(title: "Match TV mode", systemImage: "4k.tv", value: app.preferences.displayMatching.displayName)
                    }
                    #endif
                }
                SettingsSection("Channels") {
                    NavigationLink {
                        ChannelManagerView()
                    } label: {
                        SettingsRowLabel(title: "Manage channels", systemImage: "list.number", value: channelSummary)
                    }
                    NavigationLink {
                        ChannelGroupsView()
                    } label: {
                        SettingsRowLabel(title: "Channel groups", systemImage: "square.grid.2x2", value: nil)
                    }
                    NavigationLink {
                        ChannelEditorView(existing: nil)
                    } label: {
                        SettingsRowLabel(title: "Create a channel", systemImage: "plus.rectangle.on.rectangle", value: nil)
                    }
                    NavigationLink {
                        ScheduleGridPickerView()
                    } label: {
                        SettingsRowLabel(
                            title: "Program start times",
                            systemImage: "clock",
                            value: app.preferences.scheduleGrid.displayName
                        )
                    }
                }
                SettingsSection("Library") {
                    NavigationLink {
                        ServersView()
                    } label: {
                        SettingsRowLabel(title: "Servers", systemImage: "server.rack", value: serversSummary)
                    }
                    Button {
                        Task { await app.refreshLibrary() }
                    } label: {
                        SettingsRowLabel(title: "Refresh library", systemImage: "arrow.clockwise", value: refreshSummary, accessory: nil)
                    }
                    .disabled(app.isRefreshing)
                }
                SettingsSection("Account") {
                    Button {
                        isConfirmingSignOut = true
                    } label: {
                        SettingsRowLabel(title: "Sign out", systemImage: "rectangle.portrait.and.arrow.right", value: nil, accessory: nil)
                    }
                }
                SettingsSection("About") {
                    NavigationLink {
                        AcknowledgementsView()
                    } label: {
                        SettingsRowLabel(title: "Acknowledgements", systemImage: "doc.text", value: nil)
                    }
                }
                Text("\(AppIdentity.productName) \(AppIdentity.version) (\(AppIdentity.build)) · Open source under the MIT License")
                    .font(Typography.caption)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .confirmationDialog("Sign out and remove all channels from this Apple TV?", isPresented: $isConfirmingSignOut) {
            Button("Sign Out", role: .destructive) { app.signOut() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var channelSummary: String {
        let hidden = app.lineup.filter(\.isHidden).count
        let total = "\(app.lineup.count) channels"
        return hidden > .zero ? "\(total), \(hidden) hidden" : total
    }

    private var serversSummary: String {
        let count = app.servers.accounts.count
        return count == 1 ? app.servers.accounts[0].name : "\(count) servers"
    }

    private var refreshSummary: String {
        if app.isRefreshing { return "Refreshing…" }
        if let error = app.refreshError { return error }
        guard let lastRefreshed = app.lastRefreshed else { return "Never" }
        return "Updated \(ScheduleFormatting.relativeDate(lastRefreshed))"
    }
}
