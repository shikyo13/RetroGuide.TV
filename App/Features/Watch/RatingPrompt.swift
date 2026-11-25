#if os(iOS)
import RetroGuideKit
import StoreKit
import SwiftUI

/// Requests a rating on a return to the guide after qualifying full-screen playback.
private struct RatingPrompt: ViewModifier {
    private enum Timing {
        static let tick: Duration = .seconds(ScheduleConstants.secondsPerMinute)
        static let tickSeconds = ScheduleConstants.secondsPerMinute
    }

    let isWatchingFullScreen: Bool
    /// Increases each time the viewer returns to the guide.
    let finishedTasks: Int
    let tuner: Tuner

    @Environment(AppModel.self) private var app
    @Environment(AdsController.self) private var ads
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @State private var prompter = RatingPrompter()

    private var isCountingWatchTime: Bool {
        isWatchingFullScreen && scenePhase == .active && tuner.signal == .live
    }

    private var isGoodMoment: Bool {
        scenePhase == .active
            && tuner.signal == .live
            && !ads.isPresentingInterstitial
            && !app.parentalControls.policy.isEnabled
            && !(app.pro.access.showsAds && ads.isInterstitialDue)
    }

    func body(content: Content) -> some View {
        content
            .task(id: isCountingWatchTime) {
                guard isCountingWatchTime else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: Timing.tick)
                    guard !Task.isCancelled else { return }
                    prompter.recordWatching(Timing.tickSeconds)
                }
            }
            .onChange(of: finishedTasks) {
                guard isGoodMoment, prompter.isRequestDue else { return }
                prompter.requested()
                app.recordUsage(.ratingRequested)
                requestReview()
            }
    }
}

extension View {
    /// Asks for an App Store rating now and then (see ``RatingPrompt``).
    func ratingPrompt(isWatchingFullScreen: Bool, finishedTasks: Int, tuner: Tuner) -> some View {
        modifier(RatingPrompt(isWatchingFullScreen: isWatchingFullScreen, finishedTasks: finishedTasks, tuner: tuner))
    }
}
#endif
