import RetroGuideKit
import SwiftUI

/// Visibility, ordering and (for custom channels) editing of a single channel.
struct ChannelDetailView: View {
    private enum Layout {
        static let sampleShowCount = 8
    }

    let channelID: String

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    var body: some View {
        if let channel = app.lineup.first(where: { $0.id == channelID }) {
            SettingsPage(title: "\(channel.number)  \(channel.name)") {
                Text(summary(of: channel))
                    .font(Typography.body)
                    .foregroundStyle(theme.textSecondary)
                SettingsSection(String(localized: "Guide")) {
                    FavoriteChannelButton(channel: channel)
                    Button {
                        app.setHidden(!channel.isHidden, channelID: channel.id)
                    } label: {
                        SettingsRowLabel(
                            title: String(localized: "Show in guide"),
                            systemImage: channel.isHidden ? "eye.slash" : "eye",
                            value: channel.isHidden ? String(localized: "Hidden") : String(localized: "Shown"),
                            accessory: nil
                        )
                    }
                }
                ScheduleOrderSection(selection: channel.definition.ordering) { ordering in
                    app.setOrdering(ordering, for: channel.definition)
                }
                RemovedTitlesSection(channel: channel)
                if channel.definition.source == .custom {
                    SettingsSection(String(localized: "Custom channel")) {
                        NavigationLink {
                            ChannelEditorView(existing: channel.definition)
                        } label: {
                            SettingsRowLabel(title: String(localized: "Edit channel"), systemImage: "slider.horizontal.3", value: nil)
                        }
                        Button {
                            dismiss()
                            app.deleteCustomChannel(id: channel.id)
                        } label: {
                            SettingsRowLabel(title: String(localized: "Delete channel"), systemImage: "trash", value: nil, accessory: nil)
                        }
                    }
                }
            }
        } else {
            SettingsPage(title: String(localized: "Channel")) {
                Text("This channel no longer has any programs.")
                    .font(Typography.body)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private func summary(of channel: Channel) -> String {
        let shows = Array(Set(channel.items.map(\.headline))).sorted().prefix(Layout.sampleShowCount)
        let hours = ScheduleFormatting.hours(channel.totalRuntime)
        return String(localized: "\(channel.items.count) programs · \(hours)\nFeaturing \(shows.joined(separator: ", "))",
                      comment: "Channel summary; the last argument lists show names")
    }
}
