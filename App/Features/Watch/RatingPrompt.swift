#if os(iOS)
import RetroGuideKit
import StoreKit
import SwiftUI

/// Asks for an App Store rating on iPhone and iPad once enough watching has
/// passed (see ``RatingPromptPacing``). Only time spent watching a live
/// picture full screen counts, and the request comes at a calm moment:
/// opening the guide, never over the picture.
private struct RatingPrompt: ViewModifier {
    private enum Timing {
        static let tick: Duration = .seconds(ScheduleConstants.secondsPerMinute)
        static let tickSeconds = ScheduleConstants.secondsPerMinute
    }

    let isWatchingFullScreen: Bool
    let tuner: Tuner

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @State private var prompter = RatingPrompter()

    private var isCountingWatchTime: Bool {
        isWatchingFullScreen && scenePhase == .active && tuner.signal == .live
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
            .onChange(of: isWatchingFullScreen) { _, watching in
                guard !watching, scenePhase == .active, prompter.isRequestDue else { return }
                prompter.requested()
                requestReview()
            }
    }
}

extension View {
    /// Asks for an App Store rating now and then (see ``RatingPrompt``).
    func ratingPrompt(isWatchingFullScreen: Bool, tuner: Tuner) -> some View {
        modifier(RatingPrompt(isWatchingFullScreen: isWatchingFullScreen, tuner: tuner))
    }
}
#endif
