import RetroGuideKit
import SwiftUI

/// Settings home, layered over live TV (which shrinks to picture-in-picture).
struct SettingsView: View {
    /// The product name, shown untranslated.
    private static let proName = "RetroGuide Pro"

    let onClose: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var isConfirmingSignOut = false
    #if DEBUG
    @State private var debugPage = DebugLaunchOptions.settingsPage
    #endif

    var body: some View {
        ParentalSettingsGate(onCancel: onClose) {
            NavigationStack {
                SettingsPage(title: String(localized: "Settings"), onExit: onClose) {
                    SettingsSection(Self.proName) {
                        NavigationLink {
                            ProUpgradeView()
                        } label: {
                            SettingsRowLabel(
                                title: app.pro.isPro ? Self.proName : String(localized: "Upgrade to Pro"),
                                systemImage: "star.circle",
                                value: proSummary
                            )
                        }
                    }
                    SettingsSection(String(localized: "Picture")) {
                        #if os(iOS)
                        NavigationLink { WidgetSettingsView() } label: {
                            SettingsRowLabel(title: String(localized: "Home Screen widgets"), systemImage: "square.grid.2x2", value: nil)
                        }
                        #else
                        if app.pro.isPro {
                            Button { app.viewing.topShelfFavorites.toggle() } label: {
                                SettingsRowLabel(title: String(localized: "Top Shelf channels"), systemImage: "tv", value: app.viewing.topShelfFavorites ? String(localized: "Favorites") : String(localized: "Recent channels"), accessory: nil)
                            }
                        } else {
                            SettingsRowLabel(title: String(localized: "Top Shelf channels"), systemImage: "tv", value: String(localized: "Recent channels"), accessory: nil)
                            ProLockedRow(title: String(localized: "Use Favorites on Top Shelf"), systemImage: "star")
                        }
                        if app.pro.isPro && app.viewing.topShelfFavorites && !app.visibleChannels.contains(where: app.viewing.isFavorite) {
                            Text("No favorite channels are available. Add channels in Favorites below to show them on Top Shelf.")
                                .font(Typography.caption).foregroundStyle(theme.textSecondary)
                        }
                        Text("Move RetroGuide.TV to the top row of your Apple TV Home Screen to see what's on.")
                            .font(Typography.caption).foregroundStyle(theme.textSecondary)
                        #endif
                        NavigationLink {
                            ThemePickerView()
                        } label: {
                            SettingsRowLabel(title: String(localized: "Theme"), systemImage: "paintpalette", value: app.theme.name)
                        }
                        Button {
                            app.preferences.showsScanlines.toggle()
                        } label: {
                            SettingsRowLabel(
                                title: String(localized: "Scanlines on menus"),
                                systemImage: "tv",
                                value: SettingsValueText.onOff(app.preferences.showsScanlines),
                                accessory: nil
                            )
                        }
                    }
                    SettingsSection(String(localized: "Playback")) {
                        NavigationLink { PlayerEnginePickerView() } label: {
                            SettingsRowLabel(title: String(localized: "Player"), systemImage: "play.rectangle", value: app.preferences.playerEngine.displayName)
                        }
                        NavigationLink { RemindersView() } label: {
                            SettingsRowLabel(title: String(localized: "Program reminders"), systemImage: "bell", value: app.pro.isPro ? nil : "Pro")
                        }
                        #if os(tvOS)
                        NavigationLink {
                            DisplayMatchingPickerView()
                        } label: {
                            SettingsRowLabel(title: String(localized: "Match TV mode"), systemImage: "4k.tv", value: app.preferences.displayMatching.displayName)
                        }
                        #endif
                    }
                    SettingsSection(String(localized: "Channels")) {
                        NavigationLink { CommercialBreaksView() } label: {
                            SettingsRowLabel(title: String(localized: "Commercial breaks"), systemImage: "film", value: app.preferences.commercials.isEnabled ? String(localized: "Between programs") : SettingsValueText.off)
                        }
                        NavigationLink { FavoritesView() } label: {
                            SettingsRowLabel(title: String(localized: "Favorites"), systemImage: "star", value: app.pro.isPro ? app.viewing.favoriteIDs.count.formatted() : "Pro")
                        }
                        NavigationLink {
                            ChannelManagerView()
                        } label: {
                            SettingsRowLabel(title: String(localized: "Manage channels"), systemImage: "list.number", value: channelSummary)
                        }
                        if !app.parentalControls.policy.isEnabled || !app.parentalControls.policy.usesCustomLineup {
                        NavigationLink {
                            ChannelGroupsView()
                        } label: {
                            SettingsRowLabel(title: String(localized: "Channel groups"), systemImage: "square.grid.2x2", value: nil)
                        }
                        NavigationLink {
                            SimulcastLimitPickerView()
                        } label: {
                            SettingsRowLabel(title: String(localized: "Channels per show"), systemImage: "rectangle.stack", value: app.customization.simulcastLimit.displayName)
                        }
                        }
                        if removedTitleCount > .zero {
                            NavigationLink {
                                RemovedTitlesPage()
                            } label: {
                                SettingsRowLabel(title: String(localized: "Removed from channels"), systemImage: "minus.circle", value: removedTitleCount.formatted())
                            }
                        }
                        if app.pro.access.canCreateCustomChannel(existingCount: app.customization.customChannels.count) {
                            NavigationLink {
                                ChannelEditorView(existing: nil)
                            } label: {
                                SettingsRowLabel(title: String(localized: "Create a channel"), systemImage: "plus.rectangle.on.rectangle", value: nil)
                            }
                        } else {
                            ProLockedRow(title: String(localized: "Create another channel"), systemImage: "plus.rectangle.on.rectangle")
                        }
                        if app.pro.access.canChangeScheduling {
                            NavigationLink {
                                AllChannelsOrderView()
                            } label: {
                                SettingsRowLabel(
                                    title: String(localized: "Schedule order"),
                                    systemImage: "shuffle",
                                    value: AllChannelsOrdering.summary(app.customization.defaultOrdering)
                                )
                            }
                        } else {
                            ProLockedRow(title: String(localized: "Schedule order"), systemImage: "shuffle")
                        }
                        if app.pro.access.canChangeScheduling {
                            NavigationLink {
                                ScheduleGridPickerView()
                            } label: {
                                SettingsRowLabel(
                                    title: String(localized: "Program start times"),
                                    systemImage: "clock",
                                    value: app.preferences.scheduleGrid.displayName
                                )
                            }
                        } else {
                            ProLockedRow(title: String(localized: "Program start times"), systemImage: "clock")
                        }
                    }
                    SettingsSection(String(localized: "Library")) {
                        NavigationLink {
                            ServersView()
                        } label: {
                            SettingsRowLabel(title: String(localized: "Servers"), systemImage: "server.rack", value: serversSummary)
                        }
                        Button {
                            Task { await app.refreshLibrary() }
                        } label: {
                            SettingsRowLabel(title: String(localized: "Refresh library"), systemImage: "arrow.clockwise", value: refreshSummary, accessory: nil)
                        }
                        .disabled(app.isRefreshing)
                    }
                    SettingsSection(String(localized: "Account and Security")) {
                        NavigationLink { CloudSyncSettingsView() } label: {
                            SettingsRowLabel(title: String(localized: "iCloud Sync"), systemImage: "icloud", value: app.settingsSync.summary)
                        }
                        NavigationLink { ParentalControlsView() } label: {
                            SettingsRowLabel(title: String(localized: "Parental Controls"), systemImage: "lock.shield", value: SettingsValueText.onOff(app.parentalControls.policy.isEnabled))
                        }

                        Button {
                            isConfirmingSignOut = true
                        } label: {
                            SettingsRowLabel(title: String(localized: "Sign out"), systemImage: "rectangle.portrait.and.arrow.right", value: nil, accessory: nil)
                        }
                    }
                    SettingsSection(String(localized: "About")) {
                        #if os(iOS)
                        RateAppRow()
                        PrivacyChoicesRow()
                        #endif
                        NavigationLink {
                            AcknowledgementsView()
                        } label: {
                            SettingsRowLabel(title: String(localized: "Acknowledgements"), systemImage: "doc.text", value: nil)
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
        .confirmationDialog("Sign out and remove all channels from this device?", isPresented: $isConfirmingSignOut) {
            Button("Sign Out", role: .destructive) { app.signOut() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var proSummary: String {
        if app.pro.isPro { return String(localized: "Active", comment: "Settings row value: the RetroGuide Pro purchase is in effect") }
        return app.pro.product?.displayPrice ?? ProLockedRow.badge
    }

    /// Shows and movies removed from channels by hand, across every channel.
    private var removedTitleCount: Int {
        app.customization.removedTitles.values.reduce(.zero) { $0 + $1.count }
    }

    private var channelSummary: String {
        let hidden = app.lineup.filter(\.isHidden).count
        let total = app.lineup.count
        return hidden > .zero
            ? String(localized: "\(total) channels, \(hidden) hidden")
            : String(localized: "\(total) channels")
    }

    private var serversSummary: String {
        let count = app.servers.accounts.count
        return count == 1 ? app.servers.accounts[0].name : String(localized: "\(count) servers")
    }

    private var refreshSummary: String {
        if app.isRefreshing { return String(localized: "Refreshing…") }
        if let error = app.refreshError { return error }
        guard let lastRefreshed = app.lastRefreshed else {
            return String(localized: "Never", comment: "Library refresh status: the library has not been refreshed yet")
        }
        return String(localized: "Updated \(ScheduleFormatting.relativeDate(lastRefreshed))", comment: "Library refresh status; the argument is a relative time such as “5 minutes ago”")
    }
}
