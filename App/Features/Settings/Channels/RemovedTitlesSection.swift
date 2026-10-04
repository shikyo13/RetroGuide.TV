import RetroGuideKit
import SwiftUI

/// Shows and movies removed from a channel by hand, each with a way to put it back.
struct RemovedTitlesSection: View {
    let channel: Channel

    @Environment(AppModel.self) private var app

    var body: some View {
        let removed = (app.customization.removedTitles[channel.id] ?? [])
            .map { (showID: $0, name: app.titleName(showID: $0) ?? "A show no longer in your library") }
            .sorted { $0.name < $1.name }
        if !removed.isEmpty {
            SettingsSection("Removed from this channel") {
                ForEach(removed, id: \.showID) { title in
                    Button {
                        app.restoreTitle(showID: title.showID, toChannel: channel.id)
                    } label: {
                        SettingsRowLabel(title: title.name, systemImage: "arrow.uturn.backward", value: "Put back", accessory: nil)
                    }
                }
            }
        }
    }
}
