import RetroGuideKit
import SwiftUI

/// How many themed channels one show or movie may appear on.
struct ShowRepeatsPickerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    /// Shown right away on tap; rebuilding a large lineup takes a few seconds.
    @State private var pending: ShowRepeats?

    var body: some View {
        let current = pending ?? app.customization.showRepeats
        SettingsPage(title: "Show Repeats") {
            Text("Limits how many channels the same show or movie airs on, so channels feel different from each other. Everything, All Shows, 24/7 channels and your own channels aren't limited.")
                .font(Typography.body)
                .foregroundStyle(theme.textSecondary)
            VStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(ShowRepeats.allCases, id: \.self) { repeats in
                    CheckmarkRow(title: repeats.displayName, detail: repeats.explanation, isSelected: current == repeats) {
                        pending = repeats
                        app.setShowRepeats(repeats)
                    }
                }
                ScheduleUpdatingNote(isVisible: pending != nil && app.isRebuildingLineup)
            }
        }
        .onChange(of: app.isRebuildingLineup) { _, isRebuilding in
            if !isRebuilding {
                pending = nil
            }
        }
    }
}
