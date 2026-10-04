import RetroGuideKit
import SwiftUI

/// Where focus is inside the guide.
enum GuideFocus: Hashable {
    case grid
    case search
    case settings
}

/// Top bar: brand, date, clock, and the Search and Settings buttons.
/// On Apple TV, Back (or Play/Pause) jumps here from anywhere in the grid and
/// a hint says what Back does next; on iPhone and iPad a close button returns
/// to full-screen video.
struct GuideHeader: View {
    let isShowingNow: Bool
    let windowStart: Date
    let focus: FocusState<GuideFocus?>.Binding
    let actions: GuideActions

    @Environment(\.theme) private var theme
    @Environment(\.isNarrowLayout) private var isNarrowLayout
    @Environment(\.showsGuideHeaderAd) private var showsGuideHeaderAd
    @State private var width: CGFloat = .zero

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            BrandMark(showsWordmark: showsWordmark)
                .fixedSize()
            Spacer(minLength: DesignTokens.Spacing.sm)
            #if os(iOS)
            if showsAd {
                GuideHeaderAdSlot()
                Spacer(minLength: DesignTokens.Spacing.sm)
            }
            #endif
            if showsClock {
                clock
            }
            #if os(tvOS)
            backHint
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
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    #if os(iOS)
    /// The banner replaces the clock when the header is wide enough for it.
    private var showsAd: Bool {
        showsGuideHeaderAd && width >= GuideHeaderAd.minimumHeaderWidth
    }

    /// With the banner in the header, narrower phones (or Display Zoom) show only the TV glyph.
    private var showsWordmark: Bool {
        !showsAd || width >= GuideHeaderAd.wordmarkHeaderWidth
    }
    #else
    private let showsAd = false
    private let showsWordmark = true
    #endif

    /// Phones in portrait have no room for the clock; the status bar and the
    /// guide's time ruler show the time instead.
    private var showsClock: Bool {
        !isNarrowLayout && !showsAd
    }

    #if os(tvOS)
    /// What the remote's Back button does from where focus is now.
    private var backHint: some View {
        // Anywhere but the grid (including Options on the picture) is the top row.
        let isOnButtons = focus.wrappedValue != .grid
        return Label(isOnButtons ? "Back: close guide" : "Back: Search & Settings", systemImage: "chevron.backward.circle")
            .font(Typography.micro)
            .foregroundStyle(theme.textSecondary)
            .lineLimit(1)
            .fixedSize()
            .accessibilityHidden(true)
    }
    #endif

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
