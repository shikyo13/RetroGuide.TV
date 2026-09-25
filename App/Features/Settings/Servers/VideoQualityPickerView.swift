import RetroGuideKit
import SwiftUI

/// Chooses which existing copy of a title a server plays.
struct VideoQualityPickerView: View {
    let serverID: String

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        if let account = app.servers.accounts.first(where: { $0.id == serverID }) {
            SettingsPage(title: "Video Quality") {
                Text("RetroGuide.TV always plays files exactly as they are, so \(account.name) never has to convert video. When it has more than one copy of a title (for example 4K and 1080p), this picks which copy to play.")
                    .font(Typography.body)
                    .foregroundStyle(theme.textSecondary)
                VStack(spacing: DesignTokens.Spacing.sm) {
                    ForEach(VideoQuality.allCases, id: \.self) { quality in
                        CheckmarkRow(title: quality.displayName, detail: quality.explanation, isSelected: account.playback.quality == quality) {
                            var playback = account.playback
                            playback.quality = quality
                            Task { await app.updatePlayback(playback, serverID: serverID) }
                        }
                    }
                }
            }
        }
    }
}
