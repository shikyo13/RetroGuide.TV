import RetroGuideKit
import SwiftUI

struct ServerPickerStepView: View {
    private enum Layout {
        static let listWidth = PlatformMetric.value(tv: CGFloat(1_000), touch: 600)
    }

    let servers: [PlexServerCandidate]
    let onChoose: (PlexServerCandidate) -> Void
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
                    if servers.isEmpty {
                        Text("There are no additional Plex servers available on this account.")
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
            Button("Connect Jellyfin", action: onJellyfin)
                .buttonStyle(.retro)
            Button("Cancel", action: onCancel)
                .buttonStyle(.retro)
        }
        .columnWidth(Layout.listWidth)
    }
}
