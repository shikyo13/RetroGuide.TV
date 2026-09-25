import RetroGuideKit
import SwiftUI

/// Where focus is inside the guide.
enum GuideFocus: Hashable {
    case grid
    case search
    case settings
}

/// Top bar: brand, date, clock, and the Search and Settings buttons.
/// On Apple TV, Play/Pause jumps here from anywhere in the grid; on iPhone and
/// iPad a close button returns to full-screen video.
struct GuideHeader: View {
    let isShowingNow: Bool
    let windowStart: Date
    let focus: FocusState<GuideFocus?>.Binding
    let actions: GuideActions

    @Environment(\.theme) private var theme
    @Environment(\.isNarrowLayout) private var isNarrowLayout

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            BrandMark()
                .fixedSize()
            Spacer(minLength: DesignTokens.Spacing.sm)
            if showsClock {
                clock
            }
            #if os(tvOS)
            Label("Play/Pause", systemImage: "playpause")
                .font(Typography.micro)
                .foregroundStyle(theme.textSecondary)
                .accessibilityHidden(true)
            #endif
            HStack(spacing: PlatformMetric.value(tv: DesignTokens.Spacing.lg, touch: DesignTokens.Spacing.sm)) {
                Button(action: actions.onOpenSearch) {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .focused(focus, equals: .search)
                Button(action: actions.onOpenSettings) {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .focused(focus, equals: .settings)
                #if os(iOS)
                Button(action: actions.onClose) {
                    Label("Close guide", systemImage: "xmark")
                }
                #endif
            }
            #if os(tvOS)
            .buttonStyle(.retro)
            #else
            .buttonStyle(.retroIcon)
            #endif
        }
    }

    /// Phones in portrait have no room for the clock; the status bar and the
    /// guide's time ruler show the time instead.
    private var showsClock: Bool {
        !isNarrowLayout
    }

    private var clock: some View {
        TimelineView(.periodic(from: .now, by: ScheduleConstants.secondsPerMinute)) { context in
            HStack(spacing: DesignTokens.Spacing.md) {
                Text(ScheduleFormatting.day(isShowingNow ? context.date : windowStart))
                    .foregroundStyle(theme.textSecondary)
                Text(ScheduleFormatting.time(context.date))
                    .foregroundStyle(theme.accent)
            }
            .font(Typography.clock)
            .lineLimit(1)
        }
    }
}
