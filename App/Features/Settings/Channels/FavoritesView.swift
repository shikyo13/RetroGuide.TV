import RetroGuideKit
import SwiftUI

struct FavoritesView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var query = ""

    private var matchingChannels: [Channel] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return app.lineup.filter {
            search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
                || $0.callSign.localizedCaseInsensitiveContains(search) || String($0.number) == search
        }
    }

    var body: some View {
        SettingsPage(title: "Favorites") {
            if app.pro.isPro {
                SettingsSection("Browsing") {
                    Button { app.viewing.favoritesOnly.toggle() } label: {
                        SettingsRowLabel(title: "Guide & channel surfing", systemImage: "star.fill",
                                         value: app.viewing.favoritesOnly ? "Favorites" : "All channels", accessory: nil)
                    }
                }
                Text("Star channels below. Hidden and unavailable channels stay saved and return when available.")
                    .font(Typography.settingsBody).foregroundStyle(theme.textSecondary)
                TextField("Find a channel", text: $query)
                    .font(Typography.settingsBody)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .frame(minHeight: DesignTokens.Control.minimumHeight)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.medium))
                SettingsSection("Channels") {
                    if matchingChannels.isEmpty {
                        Text(query.isEmpty ? "No channels are available yet." : "No matching channels")
                            .font(Typography.settingsBody).foregroundStyle(theme.textSecondary)
                    }
                    ForEach(matchingChannels) { channel in
                        FavoriteChannelButton(channel: channel)
                    }
                }
            } else {
                ProUpgradeView()
            }
        }
    }
}

struct FavoriteChannelButton: View {
    let channel: Channel
    @Environment(AppModel.self) private var app
    @State private var showsUpgrade = false

    var body: some View {
        Button {
            if app.pro.isPro { app.viewing.toggleFavorite(channel) }
            else { showsUpgrade = true }
        } label: {
            SettingsRowLabel(title: "\(channel.number) · \(channel.name)",
                             systemImage: app.viewing.isFavorite(channel) ? "star.fill" : "star",
                             value: app.pro.isPro ? (app.viewing.isFavorite(channel) ? "Favorite" : "Add favorite") : "Pro", accessory: nil)
        }
        .sheet(isPresented: $showsUpgrade) { ProUpgradeView() }
    }
}
