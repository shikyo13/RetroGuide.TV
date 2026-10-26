import RetroGuideKit
import SwiftUI

/// One schedule order for every channel at once (RetroGuide Pro).
struct AllChannelsOrderView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    /// Shown right away on tap; rebuilding a large lineup takes a few seconds.
    @State private var pending: ScheduleOrdering??

    var body: some View {
        let current = pending ?? app.customization.defaultOrdering
        SettingsPage(title: "Schedule Order") {
            Text("Set the program order for the current lineup. You can change individual channels in Manage channels. Choosing Each channel's own restores automatic-channel defaults and keeps custom-channel orders.")
                .font(Typography.body)
                .foregroundStyle(theme.textSecondary)
            VStack(spacing: DesignTokens.Spacing.sm) {
                CheckmarkRow(
                    title: AllChannelsOrdering.eachChannelTitle,
                    detail: AllChannelsOrdering.eachChannelDetail,
                    isSelected: current == nil
                ) {
                    choose(nil)
                }
                ForEach(ScheduleOrdering.allCases, id: \.self) { ordering in
                    CheckmarkRow(title: ordering.displayName, detail: ordering.explanation, isSelected: current == ordering) {
                        choose(ordering)
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

    private func choose(_ ordering: ScheduleOrdering?) {
        pending = .some(ordering)
        app.setOrderingForAllChannels(ordering)
    }
}

enum AllChannelsOrdering {
    static let eachChannelTitle = "Each channel's own"
    static let eachChannelDetail = "Restore automatic-channel defaults. Keep custom-channel orders."

    /// For the Settings row's value.
    static func summary(_ ordering: ScheduleOrdering?) -> String {
        ordering?.displayName ?? "Per channel"
    }
}
