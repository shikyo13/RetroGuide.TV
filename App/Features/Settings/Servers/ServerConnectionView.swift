import RetroGuideKit
import SwiftUI

/// How RetroGuide.TV reaches one server: automatically, home or VPN address
/// first, or a custom address such as the server's Tailscale IP.
struct ServerConnectionView: View {
    let serverID: String

    @Environment(AppModel.self) private var app
    @State private var addressText = ""
    @State private var isApplying = false
    @State private var message: String?

    var body: some View {
        if let account = app.servers.accounts.first(where: { $0.id == serverID }) {
            SettingsPage(title: "Connection") {
                ServerConnectionStatus(account: account, isOffline: app.servers.status[serverID] == .offline, isApplying: isApplying)
                VStack(spacing: DesignTokens.Spacing.sm) {
                    ForEach(ConnectionPreference.allCases, id: \.self) { preference in
                        CheckmarkRow(
                            title: preference.displayName,
                            detail: preference.explanation,
                            isSelected: account.connection.preference == preference
                        ) {
                            choose(preference, account: account)
                        }
                    }
                }
                if account.connection.preference == .custom {
                    customAddressSection(account)
                }
                if let message {
                    Text(message).secondaryText()
                }
            }
            .onAppear {
                addressText = account.connection.customAddress.map(Self.displayAddress) ?? ""
            }
        }
    }

    private func customAddressSection(_ account: ServerAccount) -> some View {
        SettingsSection("Custom address") {
            TextField("100.x.x.x or hostname", text: $addressText)
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .onSubmit { useCustomAddress(account) }
            Button("Use this address") { useCustomAddress(account) }
                .buttonStyle(.retro)
                .disabled(isApplying || addressText.trimmingCharacters(in: .whitespaces).isEmpty)
            Text("Enter the server's Tailscale IP or another address it answers on. Port 32400 is used unless you add one, like 100.64.0.5:32400.")
                .secondaryText()
        }
    }

    private func choose(_ preference: ConnectionPreference, account: ServerAccount) {
        var connection = account.connection
        connection.preference = preference
        if preference == .custom, connection.customAddress == nil {
            // Wait for an address before switching anything.
            app.servers.saveConnectionWithoutReconnecting(connection, serverID: serverID)
            return
        }
        apply(connection)
    }

    private func useCustomAddress(_ account: ServerAccount) {
        guard let url = PlexCustomAddress.url(from: addressText, serverURL: account.baseURL) else {
            message = "That doesn't look like an address."
            return
        }
        apply(ServerConnectionSettings(preference: .custom, customAddress: url))
    }

    private func apply(_ connection: ServerConnectionSettings) {
        isApplying = true
        message = nil
        Task {
            await app.updateConnection(connection, serverID: serverID)
            isApplying = false
            if app.servers.status[serverID] == .offline {
                message = "Couldn't reach the server with this setting."
            }
        }
    }

    /// A typed IP is stored as its plex.direct form; show it as the IP again.
    private static func displayAddress(_ url: URL) -> String {
        ServerAddressText.short(url) + (url.port.map { ":\($0)" } ?? "")
    }
}

/// "Connected over VPN at 100.90.76.43" and similar.
private struct ServerConnectionStatus: View {
    let account: ServerAccount
    let isOffline: Bool
    let isApplying: Bool

    @Environment(\.theme) private var theme

    var body: some View {
        Text(text)
            .font(Typography.body)
            .foregroundStyle(theme.textSecondary)
    }

    private var text: String {
        if isApplying { return "Connecting…" }
        if isOffline { return "Can't reach \(account.name) right now." }
        let route = ConnectionRoute(account.baseURL)
        return "Connected through: \(route.displayName) (\(ServerAddressText.short(account.baseURL)))"
    }
}

/// A server address the way people recognize it: the IP inside a plex.direct
/// name, otherwise the host.
enum ServerAddressText {
    private static let plexDirectSuffix = ".plex.direct"

    static func short(_ url: URL) -> String {
        guard let host = url.host() else { return url.absoluteString }
        if host.hasSuffix(plexDirectSuffix), let first = host.split(separator: ".").first {
            return first.replacingOccurrences(of: "-", with: ".")
        }
        return host
    }
}
