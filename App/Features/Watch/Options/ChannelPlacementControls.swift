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
    @State private var isConfirmingRemoval = false
    /// The title just taken off, so it can be put back right away (the
    /// channel has moved on to something else by then).
    @State private var removed: (showID: String, name: String)?

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
        if let removed {
            note("\(removed.name) is off \(channel.name). Settings › Channels › Taken off channels lists everything you've taken off.")
            Button {
                app.restoreTitle(showID: removed.showID, toChannel: channel.id)
                self.removed = nil
            } label: {
                SettingsRowLabel(title: "Undo: put \(removed.name) back", systemImage: "arrow.uturn.backward", value: nil, accessory: nil)
            }
            .buttonStyle(.retroRow)
        }
        if channel.definition.source != .series {
            if app.pro.access.canRemoveFromChannels {
                Button {
                    isConfirmingRemoval = true
                } label: {
                    SettingsRowLabel(title: "Not on this channel", systemImage: "minus.circle", value: nil, accessory: nil)
                }
                .buttonStyle(.retroRow)
                .confirmationDialog("Take \(item.headline) off \(channel.name)?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
                    Button("Take Off", role: .destructive) {
                        removed = (item.showID, item.headline)
                        app.removeTitle(showID: item.showID, fromChannel: channel.id)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("It stays on your other channels. You can put it back any time in Settings › Channels › Taken off channels.")
                }
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
