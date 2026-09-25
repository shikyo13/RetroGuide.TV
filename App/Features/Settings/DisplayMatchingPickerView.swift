#if os(tvOS)
import RetroGuideKit
import SwiftUI

/// Chooses whether the TV switches to HDR and to each program's frame rate.
struct DisplayMatchingPickerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        SettingsPage(title: "Match TV Mode") {
            Text("Switches your TV into HDR for HDR programs, and optionally to each program's frame rate, like Apple's own player.")
                .font(Typography.body)
                .foregroundStyle(theme.textSecondary)
            if !DisplayModeController.isSystemMatchingEnabled {
                Label("Turn on Match Content in the Apple TV's Settings → Video and Audio to allow this.", systemImage: "exclamationmark.triangle")
                    .font(Typography.callout)
                    .foregroundStyle(theme.accent)
            }
            VStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(DisplayMatching.allCases) { matching in
                    CheckmarkRow(
                        title: matching.displayName,
                        detail: matching.explanation,
                        isSelected: app.preferences.displayMatching == matching
                    ) {
                        app.preferences.displayMatching = matching
                    }
                }
            }
        }
    }
}
#endif
