import RetroGuideKit
import SwiftUI

struct ParentalChannelsView: View {
    @Binding var draft: ParentalPolicy
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var previewIndex: LibraryIndex?

    var body: some View {
        SettingsPage(title: "Channels") {
            CheckmarkRow(title: "Regular lineup", detail: "Your existing channels with parental restrictions applied.",
                isSelected: !draft.usesCustomLineup) { draft.usesCustomLineup = false }
            CheckmarkRow(title: "Custom lineup", detail: "Only the channels you create here.",
                isSelected: draft.usesCustomLineup) { draft.usesCustomLineup = true }
            if draft.usesCustomLineup {
                SettingsSection("Your channels") {
                    if let previewIndex {
                        ForEach(draft.channelCustomization.customChannels) { channel in
                            NavigationLink {
                                ChannelEditorView(existing: channel, index: previewIndex, onSave: save,
                                    onDelete: { draft.channelCustomization.customChannels.removeAll { $0.id == channel.id } })
                            } label: {
                                SettingsRowLabel(title: channel.name, systemImage: "tv", value: "Edit")
                            }
                        }
                        if app.pro.access.canCreateCustomChannel(existingCount: draft.channelCustomization.customChannels.count) {
                            NavigationLink {
                                ChannelEditorView(existing: nil, index: previewIndex,
                                    nextNumber: draft.channelCustomization.nextCustomChannelNumber, onSave: save)
                            } label: {
                                SettingsRowLabel(title: "Add Channel", systemImage: "plus", value: nil)
                            }
                        } else {
                            ProLockedRow(title: "Add another channel", systemImage: "plus")
                        }
                        if draft.channelCustomization.customChannels.isEmpty {
                            Text("Add your first channel. An empty custom lineup shows no channels.")
                                .font(Typography.settingsBody).foregroundStyle(theme.textSecondary)
                        }
                    } else { ProgressView("Loading allowed content…") }
                }
            }
            Text("This lineup takes over when parental controls are on. Turning them off restores your regular lineup. All content restrictions still apply.")
                .font(Typography.settingsBody).foregroundStyle(theme.textSecondary)
            Text("Save on the Parental Controls screen to apply your changes. Cancel there discards them.")
                .font(Typography.settingsBody).foregroundStyle(theme.textSecondary)
        }
        .task {
            var policy = draft
            policy.isEnabled = true
            let snapshots = app.servers.activeSnapshots
            let quality = app.servers.qualityByServer
            let result = await Task.detached(priority: .userInitiated) {
                LibraryIndex(snapshots: policy.filtering(snapshots), quality: quality)
            }.value
            guard !Task.isCancelled else { return }
            previewIndex = result
        }
    }

    private func save(_ channel: ChannelDefinition) {
        if let index = draft.channelCustomization.customChannels.firstIndex(where: { $0.id == channel.id }) {
            draft.channelCustomization.customChannels[index] = channel
        } else {
            draft.channelCustomization.customChannels.append(channel)
        }
    }
}
