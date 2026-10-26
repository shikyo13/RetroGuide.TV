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
                Text("Choose which existing copy to prefer on \(account.name), such as 4K or 1080p. This does not set a streaming bitrate. Playback may still need conversion for compatibility.")
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
