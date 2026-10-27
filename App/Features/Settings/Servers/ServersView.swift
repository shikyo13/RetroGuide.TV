import RetroGuideKit
import SwiftUI

/// Connected servers in priority order, with their status, plus "Add a server".
struct ServersView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        SettingsPage(title: "Servers") {
            Text("Channels combine content from your selected libraries. For matching copies, servers higher in this list are preferred. Availability, parental restrictions and playable versions can affect which copy is used.")
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
                            value: "\(account.kind.displayName) · \(statusText(for: account)) · \(account.playback.quality.displayName)"
                        )
                    }
                }
                if app.pro.access.canAddServer(connectedCount: app.servers.accounts.count) {
                    NavigationLink {
                        AddServerView()
                    } label: {
                        SettingsRowLabel(title: "Add a server", systemImage: "plus.circle", value: nil)
                    }
                } else {
                    ProLockedRow(title: "Add another server", systemImage: "plus.circle")
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
