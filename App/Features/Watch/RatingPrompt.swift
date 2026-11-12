#if os(iOS)
import RetroGuideKit
import StoreKit
import SwiftUI

/// Asks for an App Store rating on iPhone and iPad once enough watching has
/// passed (see ``RatingPromptPacing``). Only time spent watching a live
/// picture full screen counts. The request comes when the viewer has just
/// finished something (back in the guide from Settings or Search), while the
/// picture plays, never with parental controls on, and never on a guide visit
/// that ends in a full-screen ad.
private struct RatingPrompt: ViewModifier {
    private enum Timing {
        static let tick: Duration = .seconds(ScheduleConstants.secondsPerMinute)
        static let tickSeconds = ScheduleConstants.secondsPerMinute
    }

    let isWatchingFullScreen: Bool
    /// Increases each time the viewer finishes a task and is back in the guide.
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
