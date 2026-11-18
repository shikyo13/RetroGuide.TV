import RetroGuideKit
import SwiftUI

/// Stars or unstars a channel (RetroGuide Pro), from Options and a channel's page.
struct FavoriteChannelButton: View {
    let channel: Channel
    /// Off where the channel is already named above (Options).
    var namesChannel = true
    @Environment(AppModel.self) private var app
    @State private var showsUpgrade = false

    var body: some View {
        Button {
            if app.pro.isPro { app.viewing.toggleFavorite(channel) }
            else { showsUpgrade = true }
        } label: {
            SettingsRowLabel(title: namesChannel ? "\(channel.number) · \(channel.name)" : String(localized: "Favorite channel"),
                             systemImage: app.viewing.isFavorite(channel) ? "star.fill" : "star",
                             value: app.pro.isPro ? favoriteValue : "Pro", accessory: nil)
        }
        .sheet(isPresented: $showsUpgrade) { ProUpgradeView() }
    }

    private var favoriteValue: String {
        app.viewing.isFavorite(channel)
            ? String(localized: "Favorite", comment: "Settings row value: this channel is a favorite")
            : String(localized: "Add favorite")
    }
}
