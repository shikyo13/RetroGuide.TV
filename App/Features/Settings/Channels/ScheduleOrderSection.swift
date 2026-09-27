import RetroGuideKit
import SwiftUI

/// Picks a channel's schedule order. Without RetroGuide Pro it shows the
/// current order and an upgrade row instead of the choices.
struct ScheduleOrderSection: View {
    let selection: ScheduleOrdering
    let onSelect: (ScheduleOrdering) -> Void

    @Environment(AppModel.self) private var app

    var body: some View {
        SettingsSection("Schedule order") {
            if app.pro.access.canChangeScheduling {
                ForEach(ScheduleOrdering.allCases, id: \.self) { ordering in
                    CheckmarkRow(title: ordering.displayName, detail: ordering.explanation, isSelected: selection == ordering) {
                        onSelect(ordering)
                    }
                }
            } else {
                CheckmarkRow(title: selection.displayName, detail: selection.explanation, isSelected: true) {}
                ProLockedRow(title: "Change schedule order", systemImage: "shuffle")
            }
        }
    }
}
