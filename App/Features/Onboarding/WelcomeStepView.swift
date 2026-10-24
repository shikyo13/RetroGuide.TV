import SwiftUI

struct WelcomeStepView: View {
    private enum Layout {
        static let textWidth = PlatformMetric.value(tv: CGFloat(1_100), touch: 560)
    }

    let onPlex: () -> Void
    let onJellyfin: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            Image(systemName: "sparkles.tv")
                .font(Typography.display)
                .foregroundStyle(theme.accent)
            Text("Your library, on the air.")
                .font(Typography.display)
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)
            Text("RetroGuide.TV turns your Plex or Jellyfin library into live TV channels with a program guide. Flip through channels, drop into whatever is on, and let the schedule do the choosing.")
                .font(Typography.body)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .columnWidth(Layout.textWidth)
            ServerKindButtons(onPlex: onPlex, onJellyfin: onJellyfin)
        }
    }
}

/// "Connect Plex" and "Connect Jellyfin", side by side.
struct ServerKindButtons: View {
    let onPlex: () -> Void
    let onJellyfin: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            Button(action: onPlex) {
                Label("Connect Plex", systemImage: "link")
            }
            .buttonStyle(.retroPrimary)
            Button(action: onJellyfin) {
                Label("Connect Jellyfin", systemImage: "link")
            }
            .buttonStyle(.retroPrimary)
        }
    }
}

/// Adding a server: which kind.
struct ServerKindStepView: View {
    let onPlex: () -> Void
    let onJellyfin: () -> Void
    let onCancel: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            Text("Add a server")
                .font(Typography.title)
                .foregroundStyle(theme.textPrimary)
            Text("Channels can mix programs from every server you add.")
                .font(Typography.body)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
            ServerKindButtons(onPlex: onPlex, onJellyfin: onJellyfin)
            Button("Cancel", action: onCancel)
                .buttonStyle(.retro)
        }
    }
}

struct ConnectingStepView: View {
    let serverName: String

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            ProgressView()
            Text("Connecting to \(serverName)…")
                .font(Typography.headline)
                .foregroundStyle(theme.textPrimary)
        }
    }
}

struct FailureStepView: View {
    let message: String
    let onRetry: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Text("Something went wrong")
                .font(Typography.title)
                .foregroundStyle(theme.textPrimary)
            Text(message)
                .font(Typography.body)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try Again", action: onRetry)
                .buttonStyle(.retroPrimary)
        }
    }
}
