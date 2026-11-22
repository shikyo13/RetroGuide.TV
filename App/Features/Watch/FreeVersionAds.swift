#if os(iOS)
import GoogleMobileAds
import RetroGuideKit
import SwiftUI
import UIKit

/// The free version's ads on iPhone and iPad: an anchored adaptive banner
/// under the menus (never over full-screen TV; in the guide header on a landscape
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
        showsAds && isWatchingFullScreen && scenePhase == .active && !ads.isPresentingInterstitial
    }

    func body(content: Content) -> some View {
        content
            .environment(\.showsGuideHeaderAd, showsBannerInGuideHeader)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .safeAreaInset(edge: .bottom, spacing: .zero) {
                if showsBanner {
                    // The strip takes exactly the width it's offered and the ad sits
                    // over it, so the ad never sizes the layout. Otherwise, when the
                    // screen narrows (iPhone Duo closing), the ad's old width holds the
                    // whole screen wide and the width that would resize it never arrives.
                    Color.clear
                        .frame(height: bannerHeightWhenShown)
                        .overlay {
                            BannerAdView(adSize: bannerSize)
                                .frame(width: cgSize(for: bannerSize).width, height: bannerHeightWhenShown)
                                // A new width gets a new banner: an existing one reloaded at
                                // another size stays blank.
                                .id(cgSize(for: bannerSize).width)
                        }
                        .clipped()
                        // Also fills the home indicator area below the strip.
                        .background(theme.surface)
                        // The ad view must never be resized frame by frame: the SDK
                        // slows down with every resize and animating it freezes the app.
                        .transition(.identity)
                        .transaction { $0.animation = nil }
                }
            }
            // Also follows the banner's height when the width changes (rotation,
            // iPhone Duo opening or closing), not only when it appears.
            .onChange(of: showsBanner ? bannerHeightWhenShown : .zero, initial: true) { _, height in
                bannerHeight = height
            }
            .task(id: app.pro.hasLoaded && !app.pro.isPro) {
                guard app.pro.hasLoaded, !app.pro.isPro else {
                    ads.discardPreloadedAd()
                    return
                }
                await ads.start()
            }
            .task(id: showsAds && scenePhase == .active) {
                guard showsAds, scenePhase == .active else { return }
                await ads.maintainInterstitial()
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
        guard showsAds, scenePhase == .active, !tuner.isPictureInPictureActive else { return }
        ads.presentInterstitialIfDue(onPresent: tuner.suspend) { [app] in
            guard UIApplication.shared.applicationState == .active, !app.sleepTimer.didExpire else { return }
            app.tuner.resume()
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
