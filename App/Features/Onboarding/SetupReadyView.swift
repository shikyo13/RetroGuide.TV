import RetroGuideKit
import SwiftUI

/// The end of first-run setup: the servers chosen so far, a slot to add
/// another Plex or Jellyfin server, and one clear button that finishes.
struct SetupReadyView: View {
    private enum Layout {
        static let columnWidth = PlatformMetric.value(tv: CGFloat(1_000), touch: 600)
    }

    let servers: [OnboardingModel.PendingServer]
    /// False without Pro once a server is chosen: the slot opens the upgrade page.
    let canAddServer: Bool
    let isStarting: Bool
    let onRemove: (String) -> Void
    let onAddServer: () -> Void
    let onShowPro: () -> Void
    let onBuild: () -> Void

    @Environment(\.theme) private var theme
    @FocusState private var focusesBuild: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("Ready to build your channels")
                    .font(Typography.title)
                    .foregroundStyle(theme.textPrimary)
                Text("Channels mix programs from every server here.")
                    .secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(servers, id: \.account.id) { server in
                    card(server)
                }
                addServerSlot
            }
            Button(action: onBuild) {
                Label("Build My Channels", systemImage: "play.tv")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.retroPrimary)
            .focused($focusesBuild)
            .disabled(servers.isEmpty || isStarting)
        }
        .columnWidth(Layout.columnWidth, alignment: .leading)
        .defaultFocus($focusesBuild, true)
    }

    private func card(_ server: OnboardingModel.PendingServer) -> some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(theme.accentSecondary)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(server.account.name)
                    .font(Typography.headline)
                    .foregroundStyle(theme.textPrimary)
                Text(detail(server))
                    .secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DesignTokens.Spacing.sm)
            Button {
                onRemove(server.account.id)
            } label: {
                Label(String(localized: "Remove \(server.account.name)"), systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.retro)
        }
        .panel(padding: DesignTokens.Spacing.md)
    }

    /// "Plex · Movies, Anime and TV Shows".
    private func detail(_ server: OnboardingModel.PendingServer) -> String {
        let libraries = server.libraries
            .filter { server.account.selectedLibraryIDs.contains($0.id) }
            .map(\.title)
            .formatted(.list(type: .and, width: .narrow))
        return [server.account.kind.displayName, libraries].joined(separator: " · ")
    }

    private var addServerSlot: some View {
        Button(action: canAddServer ? onAddServer : onShowPro) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "plus")
                Text("Add a Plex or Jellyfin server")
                Spacer(minLength: DesignTokens.Spacing.sm)
                if !canAddServer {
                    Text(ProLockedRow.badge)
                        .secondaryText()
                }
            }
        }
        .buttonStyle(.retroAddRow)
    }
}
