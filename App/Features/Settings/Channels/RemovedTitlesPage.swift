import RetroGuideKit
import SwiftUI

/// Every show and movie taken off a channel, by channel, each with a way to put it back.
struct RemovedTitlesPage: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        SettingsPage(title: "Taken off channels") {
            if app.customization.removedTitles.isEmpty {
                Text("Nothing is taken off any channel. To take a show off one, open Options while it's on and choose Not on this channel.")
                    .font(Typography.body)
                    .foregroundStyle(theme.textSecondary)
            }
            ForEach(channelIDs, id: \.self) { channelID in
                SettingsSection(channelName(channelID)) {
                    ForEach(titles(on: channelID), id: \.showID) { title in
                        Button {
                            app.restoreTitle(showID: title.showID, toChannel: channelID)
                        } label: {
                            SettingsRowLabel(title: title.name, systemImage: "arrow.uturn.backward", value: "Put back", accessory: nil)
                        }
                    }
                }
            }
        }
    }

    /// Channels with something taken off, in channel order (ones no longer in the lineup last).
    private var channelIDs: [String] {
        app.customization.removedTitles.keys.sorted { lhs, rhs in
            let left = app.lineup.first { $0.id == lhs }?.number ?? .max
            let right = app.lineup.first { $0.id == rhs }?.number ?? .max
            return left != right ? left < right : lhs < rhs
        }
    }

    private func channelName(_ channelID: String) -> String {
        app.lineup.first { $0.id == channelID }.map { "\($0.number) · \($0.name)" } ?? "A channel no longer in the lineup"
    }

    private func titles(on channelID: String) -> [(showID: String, name: String)] {
        (app.customization.removedTitles[channelID] ?? [])
            .map { (showID: $0, name: app.titleName(showID: $0) ?? "A show no longer in your library") }
            .sorted { $0.name < $1.name }
    }
}
