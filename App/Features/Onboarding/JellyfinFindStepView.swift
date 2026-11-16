import RetroGuideKit
import SwiftUI

/// Jellyfin servers found on the network, with a way to type an address
/// instead. Servers that can't be used are named with the reason.
struct JellyfinFindStepView: View {
    private enum Copy {
        static let none = "No Jellyfin servers answered on this network. Enter your server's address instead."
        static let notSecure = "Found without encryption (no HTTPS). Choose one to connect anyway."
        static func untrusted(_ hosts: [String]) -> String {
            "Found a server at \(list(hosts)) whose certificate this device doesn't trust. A self-signed certificate won't work: use one from a trusted authority, such as Let's Encrypt."
        }
        private static func list(_ hosts: [String]) -> String {
            hosts.formatted(.list(type: .or))
        }
    }

    private enum Layout {
        static let listWidth = PlatformMetric.value(tv: CGFloat(1_000), touch: 600)
        /// A home network rarely has more; others can still be typed.
        static let maxServersShown = 6
    }

    let scan: JellyfinScan
    let isSearching: Bool
    let onChoose: (JellyfinServerInfo) -> Void
    /// A server found without HTTPS, by host: offers connecting anyway.
    let onChooseNotSecure: (String) -> Void
    let onSearchAgain: () -> Void
    let onEnterAddress: () -> Void
    let onCancel: () -> Void

    @Environment(\.theme) private var theme
    @FocusState private var focusedServer: String?

    private var servers: [JellyfinServerInfo] { scan.servers }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text("Choose your Jellyfin server")
                .font(Typography.title)
                .foregroundStyle(theme.textPrimary)
            if isSearching {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    ProgressView()
                    Text("Looking for servers on your network…")
                        .secondaryText()
                }
            } else {
                if servers.isEmpty && scan.notSecure.isEmpty && scan.untrusted.isEmpty {
                    Text(Copy.none)
                        .secondaryText()
                }
                if !scan.notSecure.isEmpty {
                    Text(Copy.notSecure)
                        .secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                    notSecureRows
                }
                if !scan.untrusted.isEmpty {
                    Text(Copy.untrusted(scan.untrusted))
                        .secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !servers.isEmpty {
                serverRows
            }
            // In a row where they fit, otherwise stacked (a narrow iPhone).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DesignTokens.Spacing.md) { actions }
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) { actions }
            }
        }
        .columnWidth(Layout.listWidth)
        .defaultFocus($focusedServer, servers.first?.id ?? scan.notSecure.first)
        .onChange(of: scan) {
            focusedServer = servers.first?.id ?? scan.notSecure.first
        }
    }

    @ViewBuilder
    private var actions: some View {
        Button("Enter Address", systemImage: "keyboard", action: onEnterAddress)
            .buttonStyle(servers.isEmpty && !isSearching ? .retroPrimary : .retro)
            .fixedSize()
        if !isSearching {
            Button("Search Again", systemImage: "arrow.clockwise", action: onSearchAgain)
                .buttonStyle(.retro)
                .fixedSize()
        }
        Button("Cancel", action: onCancel)
            .buttonStyle(.retro)
            .fixedSize()
    }

    private var notSecureRows: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            ForEach(scan.notSecure.prefix(Layout.maxServersShown), id: \.self) { host in
                Button {
                    onChooseNotSecure(host)
                } label: {
                    HStack {
                        Image(systemName: "server.rack")
                        Text(host)
                        Spacer()
                        Label("Not encrypted", systemImage: "lock.open")
                            .labelStyle(.titleAndIcon)
                            .secondaryText()
                    }
                }
                .buttonStyle(.retroRow)
                .focused($focusedServer, equals: host)
            }
        }
        .padding(DesignTokens.Spacing.md)
    }

    private var serverRows: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            ForEach(servers.prefix(Layout.maxServersShown)) { server in
                Button {
                    onChoose(server)
                } label: {
                    HStack {
                        Image(systemName: "server.rack")
                        Text(server.name)
                        Spacer()
                        Text(ServerAddressText.short(server.baseURL))
                            .secondaryText()
                    }
                }
                .buttonStyle(.retroRow)
                .focused($focusedServer, equals: server.id)
            }
        }
        .padding(DesignTokens.Spacing.md)
    }
}
