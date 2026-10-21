import RetroGuideKit
import SwiftUI

/// Where focus is inside the guide.
enum GuideFocus: Hashable {
    case grid
    case favorites
    case reminder
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
    var channel: Channel?
    var program: ScheduledProgram?

    @Environment(AppModel.self) private var app
    @State private var showsUpgrade = false
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
                Button {
                    if app.pro.isPro { app.viewing.favoritesOnly.toggle() }
                    else { showsUpgrade = true }
                } label: {
                    Label(app.pro.isPro && app.viewing.favoritesOnly ? "All channels" : "Favorites", systemImage: app.pro.isPro && app.viewing.favoritesOnly ? "star.fill" : "star")
                }
                .focused(focus, equals: .favorites)
                .sheet(isPresented: $showsUpgrade) { ProUpgradeView() }
                if let channel, let program, program.start > .now {
                    ReminderButton(channel: channel, program: program)
                        .labelStyle(.iconOnly)
                        .focused(focus, equals: .reminder)
                }
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
            .fixedSize(horizontal: true, vertical: false)
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
        !isNarrowLayout && (!showsAd || width >= GuideHeaderAd.wordmarkHeaderWidth)
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
        return Label(isOnButtons ? "Back: close guide" : "Back: menus", systemImage: "chevron.backward.circle")
            .font(Typography.micro)
            .foregroundStyle(theme.textSecondary)
            .lineLimit(1)
            .fixedSize()
            .accessibilityHidden(true)
    }
    #endif

    private var clock: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: DesignTokens.Spacing.md) {
                #if os(iOS)
                Text(ScheduleFormatting.day(isShowingNow ? context.date : windowStart))
                    .foregroundStyle(theme.textSecondary)
                #endif
                Text(ScheduleFormatting.time(context.date))
                    .foregroundStyle(theme.accent)
            }
            .font(Typography.clock)
            .lineLimit(1)
        }
    }
}
