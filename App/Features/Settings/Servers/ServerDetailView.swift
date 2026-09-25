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
