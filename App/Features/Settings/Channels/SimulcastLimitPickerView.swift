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
        SettingsPage(title: "Same Show at Once") {
            Text("Keeps the same show from being on too many channels at the same moment, so flipping through channels finds something different. 24/7 channels and your own channels aren't limited.")
                .font(Typography.body)
                .foregroundStyle(theme.textSecondary)
            VStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(SimulcastLimit.allCases, id: \.self) { limit in
                    CheckmarkRow(title: limit.displayName, detail: limit.explanation, isSelected: current == limit) {
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
