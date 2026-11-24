import RetroGuideKit
import SwiftUI

/// Settings home, layered over live TV (which shrinks to picture-in-picture).
struct SettingsView: View {
    /// The product name, shown untranslated.
    private static let proName = "RetroGuide Pro"

    let onClose: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    #if DEBUG
    @State private var debugPage = DebugLaunchOptions.settingsPage
    #endif

    var body: some View {
        ParentalSettingsGate(onCancel: onClose) {
            NavigationStack {
                SettingsPage(title: String(localized: "Settings"), onExit: onClose) {
                    SettingsSection(Self.proName) {
                        NavigationLink {
                            ProUpgradeView().proEntry(.settings)
                        } label: {
                            SettingsRowLabel(
                                title: app.pro.isPro ? Self.proName : String(localized: "Upgrade to Pro"),
                                systemImage: "star.circle",
                                value: proSummary
                            )
                        }
                    }
                    SettingsSection(String(localized: "Channels")) {
                        NavigationLink { ChannelManagerView() } label: {
                            SettingsRowLabel(title: String(localized: "Channels"), systemImage: "list.number", value: channelSummary)
                        }
                        if app.pro.access.canCreateCustomChannel(existingCount: app.customization.customChannels.count) {
                            NavigationLink { ChannelEditorView(existing: nil) } label: {
                                SettingsRowLabel(title: String(localized: "Create a channel"), systemImage: "plus.rectangle.on.rectangle", value: nil)
                            }
                        } else {
                            ProLockedRow(title: String(localized: "Create another channel"), systemImage: "plus.rectangle.on.rectangle")
                                .proEntry(.channels)
                        }
                        if !app.parentalControls.policy.isEnabled || !app.parentalControls.policy.usesCustomLineup {
                            NavigationLink { ChannelGroupsView() } label: {
                                SettingsRowLabel(title: String(localized: "Channel groups"), systemImage: "square.grid.2x2", value: nil)
                            }
                        }
                    }
                    SettingsSection(String(localized: "Watching")) {
                        NavigationLink { CommercialBreaksView() } label: {
                            SettingsRowLabel(title: String(localized: "Commercial breaks"), systemImage: "film", value: app.preferences.commercials.isEnabled ? String(localized: "Between programs") : SettingsValueText.off)
                        }
                        NavigationLink { RemindersView() } label: {
                            SettingsRowLabel(title: String(localized: "Program reminders"), systemImage: "bell", value: app.pro.isPro ? nil : ProLockedRow.badge)
                        }
                        #if os(tvOS)
                        NavigationLink { DisplayMatchingPickerView() } label: {
                            SettingsRowLabel(title: String(localized: "Match TV mode"), systemImage: "4k.tv", value: app.preferences.displayMatching.displayName)
                        }
                        #endif
                    }
                    SettingsSection(String(localized: "Appearance")) {
                        NavigationLink { ThemePickerView() } label: {
                            SettingsRowLabel(title: String(localized: "Theme"), systemImage: "paintpalette", value: app.theme.name)
                        }
                        #if os(iOS)
                        NavigationLink { WidgetSettingsView() } label: {
                            SettingsRowLabel(title: String(localized: "Home Screen widgets"), systemImage: "square.grid.2x2", value: nil)
                        }
                        #else
                        TopShelfSettingsRows()
                        #endif
                    }
                    SettingsSection(String(localized: "Servers and Sync")) {
                        NavigationLink { ServersView() } label: {
                            SettingsRowLabel(title: String(localized: "Servers"), systemImage: "server.rack", value: serversSummary)
                        }
                        NavigationLink { CloudSyncSettingsView() } label: {
                            SettingsRowLabel(title: String(localized: "iCloud Sync"), systemImage: "icloud", value: app.settingsSync.summary)
                        }
                    }
                    SettingsSection(String(localized: "More")) {
                        NavigationLink { ParentalControlsView() } label: {
                            SettingsRowLabel(title: String(localized: "Parental Controls"), systemImage: "lock.shield", value: SettingsValueText.onOff(app.parentalControls.policy.isEnabled))
                        }
                        NavigationLink { AdvancedSettingsView() } label: {
                            SettingsRowLabel(title: String(localized: "Advanced"), systemImage: "slider.horizontal.3", value: nil)
                        }
                        NavigationLink { HelpAboutView() } label: {
                            SettingsRowLabel(title: String(localized: "Help and About"), systemImage: "questionmark.circle", value: nil)
                        }
                    }
                }
                #if DEBUG
                .navigationDestination(item: $debugPage) { page in
                    switch page {
                    case .theme: ThemePickerView()
                    case .pro: ProUpgradeView()
                    case .connection:
                        if let account = app.servers.accounts.first, account.kind == .jellyfin {
                            JellyfinConnectionView(serverID: account.id)
                        } else {
                            ServerConnectionView(serverID: app.servers.accounts.first?.id ?? "")
                        }
                    case .channel: ChannelDetailView(channelID: app.lineup.first?.id ?? "")
                    case .order: AllChannelsOrderView()
                    case .repeats: SimulcastLimitPickerView()
                    case .commercials: CommercialBreaksView()
                    case .cloudSync: CloudSyncSettingsView()
                    }
                }
                #endif
            }
        }
        .onDisappear { app.parentalControls.endAuthorization() }
    }

    private var proSummary: String {
        if app.pro.isPro { return String(localized: "Active", comment: "Settings row value: the RetroGuide Pro purchase is in effect") }
        return app.pro.product?.displayPrice ?? ProLockedRow.badge
    }

    /// "107 channels · Favorites 4".
    private var channelSummary: String {
        let total = String(localized: "\(app.lineup.count) channels")
        let favorites = app.lineup.filter(app.viewing.isFavorite).count
        guard app.pro.isPro, favorites > .zero else { return total }
        return total + " · " + String(localized: "Favorites \(favorites)")
    }

    private var serversSummary: String {
        let count = app.servers.accounts.count
        return count == 1 ? app.servers.accounts[0].name : String(localized: "\(count) servers")
    }
}
