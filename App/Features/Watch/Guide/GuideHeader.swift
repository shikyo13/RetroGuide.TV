import RetroGuideKit
import SwiftUI

/// Where focus is inside the guide.
enum GuideFocus: Hashable {
    case grid
    case search
    case settings
}

/// Top bar: brand, date, clock, and the Search and Settings buttons.
/// Play/Pause jumps here from anywhere in the grid.
struct GuideHeader: View {
    let isShowingNow: Bool
    let windowStart: Date
    let focus: FocusState<GuideFocus?>.Binding
    let onOpenSearch: () -> Void
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
            Label("Play/Pause", systemImage: "playpause")
                .font(Typography.micro)
                .foregroundStyle(theme.textSecondary)
                .accessibilityHidden(true)
            Button(action: onOpenSearch) {
                Label("Search", systemImage: "magnifyingglass")
            }
            .buttonStyle(.retro)
            .focused(focus, equals: .search)
            Button(action: onOpenSettings) {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .buttonStyle(.retro)
            .focused(focus, equals: .settings)
        }
    }
}
