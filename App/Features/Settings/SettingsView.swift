import RetroGuideKit
import SwiftUI

/// Settings home, layered over live TV (which shrinks to picture-in-picture).
struct SettingsView: View {
    let onClose: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var isConfirmingSignOut = false
    #if DEBUG
    @State private var debugPage = DebugLaunchOptions.settingsPage
    #endif

    var body: some View {
        NavigationStack {
            SettingsPage(title: "Settings", onExit: onClose) {
                SettingsSection("RetroGuide Pro") {
                    NavigationLink {
                        ProUpgradeView()
                    } label: {
                        SettingsRowLabel(
                            title: app.pro.isPro ? "RetroGuide Pro" : "Upgrade to Pro",
                            systemImage: "star.circle",
                            value: proSummary
                        )
                    }
                }
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
                    if app.pro.access.canCreateCustomChannel(existingCount: app.customization.customChannels.count) {
                        NavigationLink {
                            ChannelEditorView(existing: nil)
                        } label: {
                            SettingsRowLabel(title: "Create a channel", systemImage: "plus.rectangle.on.rectangle", value: nil)
                        }
                    } else {
                        ProLockedRow(title: "Create another channel", systemImage: "plus.rectangle.on.rectangle")
                    }
                    if app.pro.access.canChangeScheduling {
                        NavigationLink {
                            AllChannelsOrderView()
                        } label: {
                            SettingsRowLabel(
                                title: "Schedule order",
                                systemImage: "shuffle",
                                value: AllChannelsOrdering.summary(app.customization.defaultOrdering)
                            )
                        }
                    } else {
                        ProLockedRow(title: "Schedule order", systemImage: "shuffle")
                    }
                    if app.pro.access.canChangeScheduling {
                        NavigationLink {
                            ScheduleGridPickerView()
                        } label: {
                            SettingsRowLabel(
                                title: "Program start times",
                                systemImage: "clock",
                                value: app.preferences.scheduleGrid.displayName
                            )
                        }
                    } else {
                        ProLockedRow(title: "Program start times", systemImage: "clock")
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
                    #if os(iOS)
                    PrivacyChoicesRow()
                    #endif
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
            #if DEBUG
            .navigationDestination(item: $debugPage) { page in
                switch page {
                case .theme: ThemePickerView()
                case .pro: ProUpgradeView()
                case .connection: ServerConnectionView(serverID: app.servers.accounts.first?.id ?? "")
                case .channel: ChannelDetailView(channelID: app.lineup.first?.id ?? "")
                case .order: AllChannelsOrderView()
                }
            }
            #endif
        }
        .confirmationDialog("Sign out and remove all channels from this Apple TV?", isPresented: $isConfirmingSignOut) {
            Button("Sign Out", role: .destructive) { app.signOut() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var proSummary: String {
        if app.pro.isPro { return "Active" }
        return app.pro.product?.displayPrice ?? ProLockedRow.badge
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
