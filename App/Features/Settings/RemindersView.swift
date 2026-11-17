import SwiftUI

struct RemindersView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    var body: some View {
        SettingsPage(title: String(localized: "Program reminders")) {
            Text("Browse ahead in the guide, select a program, then choose Remind me. Reminders never change channels automatically.")
                .font(Typography.settingsBody).foregroundStyle(theme.textSecondary)
            #if os(tvOS)
            Text("On Apple TV, reminders appear while RetroGuide is open. Set reminders on your iPhone or iPad for notifications outside the app.")
                .font(Typography.settingsCaption).foregroundStyle(theme.textSecondary)
            #endif
            if !app.pro.isPro { ProLockedRow(title: String(localized: "Program reminders"), systemImage: "bell") }
            if app.reminders.pending.isEmpty {
                Text("No upcoming reminders").font(Typography.settingsBody).foregroundStyle(theme.textSecondary)
            }
            if !app.reminders.pending.isEmpty { SettingsSection(String(localized: "Upcoming")) {
                ForEach(app.reminders.pending) { reminder in
                    Button { app.reminders.remove(reminder) } label: {
                        HStack(spacing: DesignTokens.Spacing.md) {
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                                Text(reminder.title).font(Typography.settingsBodyEmphasis)
                                Text(reminder.start.formatted(date: .abbreviated, time: .shortened))
                                    .font(Typography.settingsCaption).secondaryText()
                                Text(app.channelLabel(for: reminder)).font(Typography.settingsCaption).secondaryText()
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: DesignTokens.Spacing.sm)
                            Image(systemName: "bell.slash").accessibilityHidden(true)
                        }
                    }
                    .accessibilityLabel("Cancel reminder for \(reminder.title)")
                    .accessibilityValue("\(reminder.start.formatted(date: .abbreviated, time: .shortened)), \(app.channelLabel(for: reminder))")
                    .accessibilityIdentifier("cancel-reminder-\(reminder.id)")
                }
            } }
        }
    }
}
