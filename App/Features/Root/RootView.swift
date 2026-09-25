import SwiftUI

/// Switches between the app's top-level phases.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            switch model.phase {
            case .launching:
                SplashView()
            case .onboarding:
                OnboardingFlowView()
            case let .indexing(progress):
                IndexingView(progress: progress)
            case .ready:
                WatchView()
            case let .failed(message):
                FailureView(message: message) {
                    Task { await model.retryAfterFailure() }
                }
            }
        }
        .animation(DesignTokens.Motion.relaxedEase, value: model.phase)
    }
}
