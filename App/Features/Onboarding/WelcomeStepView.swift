import SwiftUI

struct WelcomeStepView: View {
    private enum Layout {
        static let textWidth: CGFloat = 1_100
    }

    let onStart: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            Image(systemName: "sparkles.tv")
                .font(Typography.display)
                .foregroundStyle(theme.accent)
            Text("Your library, on the air.")
                .font(Typography.display)
                .foregroundStyle(theme.textPrimary)
            Text("RetroTV turns your Plex library into live TV channels with a program guide. Flip through channels, drop into whatever is on, and let the schedule do the choosing.")
                .font(Typography.body)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(width: Layout.textWidth)
            Button(action: onStart) {
                Label("Connect Plex", systemImage: "link")
            }
            .buttonStyle(.retroPrimary)
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
