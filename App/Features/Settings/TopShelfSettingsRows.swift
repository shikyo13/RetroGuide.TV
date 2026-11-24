#if os(tvOS)
import SwiftUI

/// Apple TV: which channels Top Shelf shows (favorites with RetroGuide Pro).
struct TopShelfSettingsRows: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        if app.pro.isPro {
            Button { app.viewing.topShelfFavorites.toggle() } label: {
                SettingsRowLabel(title: String(localized: "Top Shelf channels"), systemImage: "tv", value: app.viewing.topShelfFavorites ? String(localized: "Favorites") : String(localized: "Recent channels"), accessory: nil)
            }
            if app.viewing.topShelfFavorites && !app.visibleChannels.contains(where: app.viewing.isFavorite) {
                Text("No favorite channels are available. Star channels in Settings › Channels to show them on Top Shelf.")
                    .font(Typography.caption).foregroundStyle(theme.textSecondary)
            }
        } else {
            ProLockedRow(title: String(localized: "Use Favorites on Top Shelf"), systemImage: "star").proEntry(.topShelf)
        }
        Text("Move RetroGuide.TV to the top row of your Apple TV Home Screen to see what's on.")
            .font(Typography.caption).foregroundStyle(theme.textSecondary)
    }
}
#endif
