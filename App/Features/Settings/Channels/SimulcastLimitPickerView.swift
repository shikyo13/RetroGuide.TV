import RetroGuideKit
import SwiftUI

/// How many channels may air the same show at the same time.
struct SimulcastLimitPickerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    /// Shown right away on tap; rebuilding a large lineup takes a few seconds.
    @State private var pending: SimulcastLimit?

    var body: some View {
        let current = pending ?? app.customization.simulcastLimit
        SettingsPage(title: "Channels per Show") {
            Text(current.explanation)
                .font(Typography.body).foregroundStyle(theme.textSecondary)
            Text("Applies to automatic channels. 24/7 and custom channels are excluded from this limit. If no other show can fill a slot, the limit may be exceeded.")
                .font(Typography.body).foregroundStyle(theme.textSecondary)
            Text("The scheduler also avoids airing the exact same episode or movie on multiple channels when alternatives are available.")
                .font(Typography.body).foregroundStyle(theme.textSecondary)
            VStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(SimulcastLimit.allCases, id: \.self) { limit in
                    CheckmarkRow(title: limit.displayName, isSelected: current == limit) {
                        pending = limit
                        app.setSimulcastLimit(limit)
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
