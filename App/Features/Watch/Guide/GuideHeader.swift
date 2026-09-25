import RetroTVKit
import SwiftUI

/// Top bar: brand, date, clock and the Settings button.
struct GuideHeader: View {
    let isShowingNow: Bool
    let windowStart: Date
    let onOpenSettings: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            BrandMark()
            Spacer()
            TimelineView(.periodic(from: .now, by: ScheduleConstants.secondsPerMinute)) { context in
                HStack(spacing: DesignTokens.Spacing.md) {
                    Text(ScheduleFormatting.day(isShowingNow ? context.date : windowStart))
                        .foregroundStyle(theme.textSecondary)
                    Text(ScheduleFormatting.time(context.date))
                        .foregroundStyle(theme.accent)
                }
                .font(Typography.clock)
            }
            Button(action: onOpenSettings) {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .buttonStyle(.retro)
        }
    }
}
