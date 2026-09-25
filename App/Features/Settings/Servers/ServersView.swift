import RetroGuideKit
import SwiftUI

/// Connected servers in priority order, with their status, plus "Add a server".
struct ServersView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        SettingsPage(title: "Servers") {
            Text("Channels mix content from every server. When the same show or movie is on more than one server, it plays from the first server listed.")
                .font(Typography.body)
                .foregroundStyle(theme.textSecondary)
            SettingsSection("Connected") {
                ForEach(app.servers.accounts) { account in
                    NavigationLink {
                        ServerDetailView(serverID: account.id)
                    } label: {
                        SettingsRowLabel(
                            title: account.name,
                            systemImage: statusSymbol(for: account),
                            value: "\(account.kind.displayName) · \(statusText(for: account))"
                        )
                    }
                }
                NavigationLink {
                    AddServerView()
                } label: {
                    SettingsRowLabel(title: "Add a server", systemImage: "plus.circle", value: nil)
                }
            }
        }
    }

    private func statusText(for account: ServerAccount) -> String {
        app.servers.status[account.id] == .offline ? "Offline" : "Online"
    }

    private func statusSymbol(for account: ServerAccount) -> String {
        app.servers.status[account.id] == .offline ? "exclamationmark.triangle" : "server.rack"
    }
}
