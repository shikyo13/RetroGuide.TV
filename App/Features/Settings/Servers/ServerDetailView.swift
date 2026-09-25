import RetroGuideKit
import SwiftUI

/// One server: its libraries and removal.
struct ServerDetailView: View {
    let serverID: String

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var isConfirmingRemoval = false

    var body: some View {
        if let account = app.servers.accounts.first(where: { $0.id == serverID }) {
            SettingsPage(title: account.name) {
                Text(app.servers.status[serverID] == .offline
                    ? "This server can't be reached right now. Its programs are left out of the guide until it's back."
                    : "Connected at \(account.baseURL.host() ?? account.baseURL.absoluteString).")
                    .font(Typography.body)
                    .foregroundStyle(theme.textSecondary)
                SettingsSection("Playback") {
                    NavigationLink {
                        VideoQualityPickerView(serverID: serverID)
                    } label: {
                        SettingsRowLabel(title: "Video quality", systemImage: "sparkles.tv", value: account.playback.quality.displayName)
                    }
                    Button {
                        var playback = account.playback
                        playback.extraBuffering.toggle()
                        Task { await app.updatePlayback(playback, serverID: serverID) }
                    } label: {
                        SettingsRowLabel(
                            title: "Extra buffering",
                            systemImage: "gauge.with.dots.needle.33percent",
                            value: account.playback.extraBuffering ? "On" : "Off",
                            accessory: nil
                        )
                    }
                    Text("Extra buffering reads further ahead so playback rides out slow or uneven internet. Turn it on for servers outside your home.")
                        .font(Typography.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                SettingsSection("Server") {
                    NavigationLink {
                        LibrarySettingsView(account: account)
                    } label: {
                        SettingsRowLabel(title: "Libraries", systemImage: "books.vertical", value: nil)
                    }
                    Button {
                        isConfirmingRemoval = true
                    } label: {
                        SettingsRowLabel(title: "Remove server", systemImage: "trash", value: nil, accessory: nil)
                    }
                }
            }
            .confirmationDialog("Remove \(account.name)? Its programs will leave every channel.", isPresented: $isConfirmingRemoval) {
                Button("Remove", role: .destructive) {
                    dismiss()
                    Task { await app.removeServer(id: serverID) }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
