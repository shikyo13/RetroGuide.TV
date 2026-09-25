import RetroTVKit
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
                SettingsSection("Guide") {
                    Button {
                        app.setHidden(!channel.isHidden, channelID: channel.id)
                    } label: {
                        SettingsRowLabel(
                            title: "Show in guide",
                            systemImage: channel.isHidden ? "eye.slash" : "eye",
                            value: channel.isHidden ? "Hidden" : "Shown",
                            accessory: nil
                        )
                    }
                }
                SettingsSection("Schedule order") {
                    ForEach(ScheduleOrdering.allCases, id: \.self) { ordering in
                        CheckmarkRow(
                            title: ordering.displayName,
                            detail: ordering.explanation,
                            isSelected: channel.definition.ordering == ordering
                        ) {
                            app.setOrdering(ordering, for: channel.definition)
                        }
                    }
                }
                if channel.definition.source == .custom {
                    SettingsSection("Custom channel") {
                        NavigationLink {
                            ChannelEditorView(existing: channel.definition)
                        } label: {
                            SettingsRowLabel(title: "Edit channel", systemImage: "slider.horizontal.3", value: nil)
                        }
                        Button {
                            dismiss()
                            app.deleteCustomChannel(id: channel.id)
                        } label: {
                            SettingsRowLabel(title: "Delete channel", systemImage: "trash", value: nil, accessory: nil)
                        }
                    }
                }
            }
        } else {
            SettingsPage(title: "Channel") {
                Text("This channel no longer has any programs.")
                    .font(Typography.body)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private func summary(of channel: Channel) -> String {
        let shows = Array(Set(channel.items.map(\.headline))).sorted().prefix(Layout.sampleShowCount)
        let stats = "\(channel.items.count) programs · \(ScheduleFormatting.hours(channel.totalRuntime))"
        return "\(stats)\nFeaturing \(shows.joined(separator: ", "))"
    }
}
