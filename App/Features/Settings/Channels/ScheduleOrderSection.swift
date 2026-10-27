import RetroGuideKit
import SwiftUI

/// Picks a channel's schedule order. Without RetroGuide Pro it shows the
/// current order and an upgrade row instead of the choices.
struct ScheduleOrderSection: View {
    let selection: ScheduleOrdering
    let onSelect: (ScheduleOrdering) -> Void

    @Environment(AppModel.self) private var app
    /// Shown right away on tap; rebuilding a large lineup takes a few seconds.
    @State private var pending: ScheduleOrdering?

    var body: some View {
        SettingsSection("Schedule order") {
            if app.pro.access.canChangeScheduling {
                ForEach(ScheduleOrdering.allCases, id: \.self) { ordering in
                    CheckmarkRow(title: ordering.displayName, detail: ordering.explanation, isSelected: (pending ?? selection) == ordering) {
                        pending = ordering
                        onSelect(ordering)
                    }
                }
                ScheduleUpdatingNote(isVisible: pending != nil && app.isRebuildingLineup)
            } else {
                CheckmarkRow(title: selection.displayName, detail: selection.explanation, isSelected: true) {}
                ProLockedRow(title: "Change schedule order", systemImage: "shuffle")
            }
        }
        .onChange(of: selection) { _, newValue in
            if newValue == pending {
                pending = nil
            }
        }
    }
}

/// "Updating the schedule…" with a spinner, while channels are rebuilt.
struct ScheduleUpdatingNote: View {
    let isVisible: Bool

    var body: some View {
        if isVisible {
            HStack(spacing: DesignTokens.Spacing.sm) {
                ProgressView()
                Text("Updating the schedule…").secondaryText()
            }
        }
    }
}
