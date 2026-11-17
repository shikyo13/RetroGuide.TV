import RetroGuideKit
import SwiftUI

struct ServerPickerStepView: View {
    private enum Copy {
        static let noServers = String(localized: "This Plex account has no servers yet: none of its own and none shared with it. RetroGuide.TV plays the movies and shows on a Plex or Jellyfin server, either your own or one a friend has shared with you. If a server was shared with a different Plex account, sign in with that one.")
        static let allAdded = String(localized: "Every Plex server on this account is already added.")
    }

    private enum Layout {
        static let listWidth = PlatformMetric.value(tv: CGFloat(1_000), touch: 600)
    }

    let servers: [PlexServerCandidate]
    /// False when the account has no server, neither its own nor shared with it.
    let accountHasServers: Bool
    let onChoose: (PlexServerCandidate) -> Void
    let onAnotherAccount: () -> Void
    let onJellyfin: () -> Void
    let onCancel: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text("Choose a server")
                .font(Typography.title)
                .foregroundStyle(theme.textPrimary)
            ScrollView {
                VStack(spacing: DesignTokens.Spacing.sm) {
                    if !accountHasServers {
                        Text(Copy.noServers)
                            .secondaryText()
                            .fixedSize(horizontal: false, vertical: true)
                    } else if servers.isEmpty {
                        Text(Copy.allAdded)
                            .secondaryText()
                    }
                    ForEach(servers) { server in
                        Button {
                            onChoose(server)
                        } label: {
                            HStack {
                                Image(systemName: "server.rack")
                                Text(server.name)
                                Spacer()
                                Text(server.isOwned ? "Your server" : "Shared with you")
                                    .secondaryText()
                            }
                        }
                        .buttonStyle(.retroRow)
                    }
                }
                .padding(DesignTokens.Spacing.md)
            }
            if !accountHasServers {
                Button("Use Another Plex Account", systemImage: "person.crop.circle", action: onAnotherAccount)
                    .buttonStyle(.retroPrimary)
            }
            Button("Connect Jellyfin", action: onJellyfin)
                .buttonStyle(.retro)
            Button("Cancel", action: onCancel)
                .buttonStyle(.retro)
        }
        .columnWidth(Layout.listWidth)
    }
}
