import RetroGuideKit
import SwiftUI

/// Connected servers with their status, "Add a server", refreshing the
/// library, and removing every server.
struct ServersView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var isConfirmingRemoveAll = false

    var body: some View {
        SettingsPage(title: String(localized: "Servers")) {
            SettingsSection(String(localized: "Connected")) {
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
                        SettingsRowLabel(title: String(localized: "Add a server"), systemImage: "plus.circle", value: nil)
                    }
                } else {
                    ProLockedRow(title: String(localized: "Add another server"), systemImage: "plus.circle").proEntry(.servers)
                }
            }
            SettingsSection(String(localized: "Library")) {
                Button {
                    Task { await app.refreshLibrary() }
                } label: {
                    SettingsRowLabel(title: String(localized: "Refresh library"), systemImage: "arrow.clockwise", value: refreshSummary, accessory: nil)
                }
                .disabled(app.isRefreshing)
                Button(role: .destructive) {
                    isConfirmingRemoveAll = true
                } label: {
                    SettingsRowLabel(title: String(localized: "Remove all servers"), systemImage: "trash", value: nil, accessory: nil)
                }
            }
        }
        .confirmationDialog("Remove all servers and channels from this device?", isPresented: $isConfirmingRemoveAll, titleVisibility: .visible) {
            Button("Remove All Servers", role: .destructive) { app.signOut() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var refreshSummary: String {
        if app.isRefreshing { return String(localized: "Refreshing…") }
        if let error = app.refreshError { return error }
        guard let lastRefreshed = app.lastRefreshed else {
            return String(localized: "Never", comment: "Library refresh status: the library has not been refreshed yet")
        }
        return String(localized: "Updated \(ScheduleFormatting.relativeDate(lastRefreshed))", comment: "Library refresh status; the argument is a relative time such as “5 minutes ago”")
    }

    private func statusText(for account: ServerAccount) -> String {
        app.servers.status[account.id] == .offline
            ? String(localized: "Offline", comment: "Server status")
            : String(localized: "Online", comment: "Server status")
    }

    private func statusSymbol(for account: ServerAccount) -> String {
        app.servers.status[account.id] == .offline ? "exclamationmark.triangle" : "server.rack"
    }
}
