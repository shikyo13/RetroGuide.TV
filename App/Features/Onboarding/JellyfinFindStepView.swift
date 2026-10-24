import RetroGuideKit
import SwiftUI

/// Jellyfin servers found on the network, with a way to type an address instead.
struct JellyfinFindStepView: View {
    private enum Layout {
        static let listWidth = PlatformMetric.value(tv: CGFloat(1_000), touch: 600)
    }

    let servers: [JellyfinServerInfo]
    let isSearching: Bool
    let onChoose: (JellyfinServerInfo) -> Void
    let onSearchAgain: () -> Void
    let onEnterAddress: () -> Void
    let onCancel: () -> Void

    @Environment(\.theme) private var theme

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
            } else if servers.isEmpty {
                Text("No Jellyfin servers answered on this network. Enter your server's address instead.")
                    .secondaryText()
            }
            if !servers.isEmpty {
                ScrollView {
                    VStack(spacing: DesignTokens.Spacing.sm) {
                        ForEach(servers) { server in
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
                        }
                    }
                    .padding(DesignTokens.Spacing.md)
                }
            }
            HStack(spacing: DesignTokens.Spacing.md) {
                Button("Enter Address", systemImage: "keyboard", action: onEnterAddress)
                    .buttonStyle(servers.isEmpty && !isSearching ? .retroPrimary : .retro)
                if !isSearching {
                    Button("Search Again", systemImage: "arrow.clockwise", action: onSearchAgain)
                        .buttonStyle(.retro)
                }
                Button("Cancel", action: onCancel)
                    .buttonStyle(.retro)
            }
        }
        .columnWidth(Layout.listWidth)
    }
}
