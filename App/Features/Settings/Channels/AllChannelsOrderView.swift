import RetroGuideKit
import SwiftUI

/// One schedule order for every channel at once (RetroGuide Pro).
struct AllChannelsOrderView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    /// Shown right away on tap; rebuilding a large lineup takes a few seconds.
    @State private var pending: ScheduleOrdering??
    /// An order for every channel replaces the choices made per channel.
    @State private var confirming: ScheduleOrdering?

    var body: some View {
        let current = pending ?? app.customization.defaultOrdering
        SettingsPage(title: String(localized: "Schedule order for all channels")) {
            Text("Use one program order on every channel. To change a single channel, open it in Settings › Channels.")
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
                ForEach(ScheduleOrdering.allChannelsChoices, id: \.self) { ordering in
                    CheckmarkRow(title: ordering.displayName, detail: ordering.explanation, isSelected: current == ordering) {
                        if current != ordering { confirming = ordering }
                    }
                }
                ScheduleUpdatingNote(isVisible: pending != nil && app.isRebuildingLineup)
            }
        }
        .confirmationDialog(
            confirming.map { String(localized: "Use \($0.displayName) on every channel?") } ?? "",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Use on Every Channel")) {
                if let confirming { choose(confirming) }
                confirming = nil
            }
            Button("Cancel", role: .cancel) { confirming = nil }
        } message: {
            Text("This replaces the order chosen for each channel, including your own channels.")
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
    static var eachChannelTitle: String {
        String(localized: "Each channel's own", comment: "Schedule order choice: every channel keeps its own order")
    }
    static var eachChannelDetail: String {
        String(localized: "Restore automatic-channel defaults. Keep custom-channel orders.")
    }

    /// For the Settings row's value.
    static func summary(_ ordering: ScheduleOrdering?) -> String {
        ordering?.displayName ?? String(localized: "Per channel", comment: "Settings row value: each channel has its own schedule order")
    }
}
