import SwiftUI

/// Chooses between the bundled universal player and Apple's player.
struct PlayerEnginePickerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        SettingsPage(title: "Player") {
            Text("RetroTV plays the original files from your server whenever it can, so your server doesn't have to convert video.")
                .font(Typography.body)
                .foregroundStyle(theme.textSecondary)
            VStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(PlaybackEngineKind.allCases) { kind in
                    CheckmarkRow(
                        title: kind.displayName,
                        detail: kind.explanation,
                        isSelected: app.preferences.playerEngine == kind
                    ) {
                        app.preferences.playerEngine = kind
                    }
                }
            }
        }
    }
}
