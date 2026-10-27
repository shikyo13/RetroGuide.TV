import RetroGuideKit
import SwiftUI

struct WidgetSettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        SettingsPage(title: "Home Screen") {
            Text("Add What's On for artwork, current programs and channel controls, or App Icon for a larger icon. Both follow your app theme.")
                .font(Typography.settingsBody).foregroundStyle(theme.textSecondary)
            Text("Touch and hold your Home Screen, choose Edit › Add Widget, then search for RetroGuide.TV. Reopen the app to refresh the saved schedule; iOS decides when widgets update.")
                .font(Typography.settingsBody).foregroundStyle(theme.textSecondary)
            if app.pro.isPro {
                SettingsSection("What's On channels") {
                    ForEach(ViewingPreferences.WidgetSource.allCases, id: \.self) { source in
                        Button { app.viewing.widgetSource = source } label: {
                            SettingsRowLabel(title: source.title, systemImage: app.viewing.widgetSource == source ? "checkmark.circle.fill" : "circle", value: nil, accessory: nil)
                        }
                        .accessibilityValue(app.viewing.widgetSource == source ? "Selected" : "Not selected")
                    }
                }
                if app.viewing.widgetSource == .favorites {
                    if !app.visibleChannels.contains(where: app.viewing.isFavorite) {
                        Text("No favorite channels are available. Choose Favorites below to add channels to your widget.")
                            .font(Typography.settingsBody).foregroundStyle(theme.textSecondary)
                    }
                    NavigationLink { FavoritesView() } label: {
                        SettingsRowLabel(title: "Choose Favorites", systemImage: "star", value: nil)
                    }
                    .buttonStyle(.retroRow)
                }
                if app.viewing.widgetSource == .selected || app.viewing.widgetSource == .pinned {
                    Text(app.viewing.widgetSource == .pinned ? "Pin one channel to stop automatic rotation." : "Choose up to \(ViewingPreferences.Limits.widgetChannels) channels.")
                        .font(Typography.settingsBody).foregroundStyle(theme.textSecondary)
                    if !app.visibleChannels.contains(where: { selected($0.id) }) {
                        Text("Choose a channel below to show programs in your widget.")
                            .font(Typography.settingsBody).foregroundStyle(theme.textSecondary)
                    }
                    SettingsSection("Channels") {
                        ForEach(app.visibleChannels) { channel in
                            Button { select(channel.id) } label: {
                                SettingsRowLabel(title: "\(channel.number) · \(channel.name)", systemImage: selected(channel.id) ? "checkmark.circle.fill" : "circle", value: nil, accessory: nil)
                            }
                            .accessibilityValue(selected(channel.id) ? "Selected" : "Not selected")
                            .disabled(app.viewing.widgetSource == .selected && !selected(channel.id) && app.viewing.widgetChannelIDs.count >= ViewingPreferences.Limits.widgetChannels)
                        }
                    }
                }
            } else {
                ProLockedRow(title: "Customize widget channels", systemImage: "slider.horizontal.3")
            }
        }
    }

    private func selected(_ id: String) -> Bool {
        app.viewing.widgetSource == .pinned ? app.viewing.pinnedChannelID == id : app.viewing.widgetChannelIDs.contains(id)
    }

    private func select(_ id: String) {
        if app.viewing.widgetSource == .pinned { app.viewing.pinnedChannelID = id }
        else if selected(id) { app.viewing.widgetChannelIDs.remove(id) }
        else { app.viewing.widgetChannelIDs.insert(id) }
    }
}
