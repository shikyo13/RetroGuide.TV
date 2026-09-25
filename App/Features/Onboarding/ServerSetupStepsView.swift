import RetroGuideKit
import SwiftUI

/// The steps of connecting a server (link, choose server, choose libraries),
/// shared by first-run onboarding and "Add a server" in Settings.
struct ServerSetupStepsView: View {
    let model: OnboardingModel
    let onCancel: () -> Void
    let onComplete: (OnboardingModel.PendingServer, Set<String>) -> Void

    var body: some View {
        Group {
            switch model.step {
            case .welcome:
                WelcomeStepView(onStart: model.begin)
            case let .linking(code):
                PlexLinkStepView(code: code, onCancel: onCancel)
            case let .choosingServer(servers):
                ServerPickerStepView(servers: servers, onChoose: model.choose)
            case let .connecting(name):
                ConnectingStepView(serverName: name)
            case let .choosingLibraries(pending):
                LibraryPickerView(libraries: pending.libraries, confirmTitle: "Build My Channels") { selected in
                    onComplete(pending, selected)
                }
            case let .failed(message):
                FailureStepView(message: message, onRetry: model.begin)
            }
        }
        .transition(.opacity)
        .animation(DesignTokens.Motion.standardEase, value: model.step)
    }
}
