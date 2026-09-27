#if os(iOS)
import GoogleMobileAds
import RetroGuideKit
import SwiftUI

/// The free version's ads on iPhone and iPad: a standard banner under the
/// menus (never over full-screen TV; in the guide header on a landscape
/// iPhone, where height is scarce), and a full-screen ad at a natural break
/// once 90 minutes of watching have passed.
/// Natural breaks are closing the guide and a program ending on the channel
/// being watched; the channel pauses during the ad and rejoins live after.
private struct FreeVersionAds: ViewModifier {
    private enum Timing {
        static let tick: Duration = .seconds(ScheduleConstants.secondsPerMinute)
        static let tickSeconds = ScheduleConstants.secondsPerMinute
    }

    let isWatchingFullScreen: Bool
    let isGuideOpen: Bool
    let tuner: Tuner
    @Binding var bannerHeight: CGFloat

    @Environment(AppModel.self) private var app
    @Environment(AdsController.self) private var ads
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isShortLayout) private var isShortLayout
    @Environment(\.theme) private var theme
    @State private var width: CGFloat = .zero
    @State private var lastTuneGeneration = 0

    private var showsAds: Bool {
        app.pro.access.showsAds && ads.isReady
    }

    /// Landscape iPhone guide: the banner moves into the guide header instead.
    private var showsBannerInGuideHeader: Bool {
        showsAds && isGuideOpen && isShortLayout
    }

    private var showsBanner: Bool {
        showsAds && !isWatchingFullScreen && !showsBannerInGuideHeader && width > .zero
    }

    private var bannerSize: AdSize {
        BannerAdView.adSize(fitting: width)
    }

    private var bannerHeightWhenShown: CGFloat {
        cgSize(for: bannerSize).height
    }

    private var isCountingWatchTime: Bool {
        showsAds && isWatchingFullScreen && scenePhase == .active
    }

    func body(content: Content) -> some View {
        content
            .environment(\.showsGuideHeaderAd, showsBannerInGuideHeader)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .safeAreaInset(edge: .bottom, spacing: .zero) {
                if showsBanner {
                    BannerAdView(adSize: bannerSize)
                        .frame(width: cgSize(for: bannerSize).width, height: bannerHeightWhenShown)
                        .clipped()
                        .frame(maxWidth: .infinity)
                        .background(theme.surface)
                        // The ad view must never be resized frame by frame: the SDK
                        // slows down with every resize and animating it freezes the app.
                        .transition(.identity)
                        .transaction { $0.animation = nil }
                }
            }
            .onChange(of: showsBanner, initial: true) { _, shown in
                bannerHeight = shown ? bannerHeightWhenShown : .zero
            }
            .task(id: app.pro.hasLoaded && !app.pro.isPro) {
                guard app.pro.hasLoaded, !app.pro.isPro else { return }
                await ads.start()
            }
            .task(id: isCountingWatchTime) {
                guard isCountingWatchTime else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: Timing.tick)
                    guard !Task.isCancelled else { return }
                    ads.recordWatching(Timing.tickSeconds)
                }
            }
            .onChange(of: isWatchingFullScreen) { _, watching in
                if watching { naturalBreak() }
            }
            .onChange(of: tuner.program?.id) {
                // A new program on the same tune is a program ending, not a channel change.
                if isWatchingFullScreen, tuner.tuneGeneration == lastTuneGeneration {
                    naturalBreak()
                }
                lastTuneGeneration = tuner.tuneGeneration
            }
    }

    private func naturalBreak() {
        guard showsAds else { return }
        ads.presentInterstitialIfDue(onPresent: tuner.suspend) { [tuner] in
            tuner.resume()
        }
    }
}

extension View {
    /// Ads for the free version (see ``FreeVersionAds``). `bannerHeight`
    /// reports the room the banner takes at the bottom of the screen.
    func freeVersionAds(
        isWatchingFullScreen: Bool,
        isGuideOpen: Bool,
        tuner: Tuner,
        bannerHeight: Binding<CGFloat>
    ) -> some View {
        modifier(FreeVersionAds(
            isWatchingFullScreen: isWatchingFullScreen,
            isGuideOpen: isGuideOpen,
            tuner: tuner,
            bannerHeight: bannerHeight
        ))
    }
}
#endif
