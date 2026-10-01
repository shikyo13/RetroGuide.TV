import RetroGuideKit
import SwiftUI

/// "Why is this here?" for what's on, and (with RetroGuide Pro) taking it off
/// the channel when it doesn't belong.
struct ChannelPlacementControls: View {
    let channel: Channel
    let item: MediaItem

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var isExplaining = false
    /// The title just taken off, named after the channel has moved on to something else.
    @State private var removedTitle: String?

    var body: some View {
        controls
            // A new program has its own reasons.
            .onChange(of: item.showID) { isExplaining = false }
    }

    @ViewBuilder
    private var controls: some View {
        Button {
            isExplaining.toggle()
        } label: {
            SettingsRowLabel(title: "Why is this here?", systemImage: "questionmark.circle", value: nil, accessory: isExplaining ? "chevron.up" : "chevron.down")
        }
        .buttonStyle(.retroRow)
        if isExplaining {
            note(PlacementText.explanation(
                of: app.libraryIndex.placement(of: item, under: channel.definition.rule),
                title: item.headline,
                on: channel
            ))
        }
        if let removedTitle {
            note("\(removedTitle) is off \(channel.name). To put it back: Settings › Channels › \(channel.name).")
        }
        if channel.definition.source != .series {
            if app.pro.access.canRemoveFromChannels {
                Button {
                    removedTitle = item.headline
                    app.removeTitle(showID: item.showID, fromChannel: channel.id)
                } label: {
                    SettingsRowLabel(title: "Not on this channel", systemImage: "minus.circle", value: nil, accessory: nil)
                }
                .buttonStyle(.retroRow)
            } else {
                note("Taking a show off a channel is part of RetroGuide Pro (Settings › RetroGuide Pro).")
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Typography.body)
            .foregroundStyle(theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
