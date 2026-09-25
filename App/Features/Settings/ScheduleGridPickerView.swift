import RetroGuideKit
import SwiftUI

/// Chooses whether programs air back to back or start on a broadcast grid.
struct ScheduleGridPickerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        SettingsPage(title: "Program Start Times") {
            Text("Real TV starts shows on the hour and half hour. Aligning to a grid adds a short \"We'll be right back\" break between programs so the guide lines up neatly.")
                .font(Typography.body)
                .foregroundStyle(theme.textSecondary)
            VStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(ScheduleGrid.allCases, id: \.self) { grid in
                    CheckmarkRow(title: grid.displayName, isSelected: app.preferences.scheduleGrid == grid) {
                        app.preferences.scheduleGrid = grid
                    }
                }
            }
        }
    }
}
