import RetroTVKit
import SwiftUI

/// Hosts the onboarding steps with a shared header and background.
struct OnboardingFlowView: View {
    @Environment(AppModel.self) private var app
    @State private var model: OnboardingModel?

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            BrandMark()
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: .zero)
            if let model {
                content(for: model)
                    .transition(.opacity)
            }
            Spacer(minLength: .zero)
        }
        .animation(DesignTokens.Motion.standardEase, value: model?.step)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .crtEffect()
        .onAppear {
            if model == nil {
                model = OnboardingModel(identity: app.plexIdentity)
            }
        }
    }

    @ViewBuilder
    private func content(for model: OnboardingModel) -> some View {
        switch model.step {
        case .welcome:
            WelcomeStepView(onStart: model.beginPlexLink)
        case let .linking(code):
            PlexLinkStepView(code: code, onCancel: model.cancel)
        case let .choosingServer(servers):
            ServerPickerStepView(servers: servers, onChoose: model.choose)
        case let .connecting(name):
            ConnectingStepView(serverName: name)
        case let .choosingLibraries(pending):
            LibraryPickerView(libraries: pending.libraries, confirmTitle: "Build My Channels") { selected in
                var account = pending.account
                account.selectedLibraryIDs = selected
                Task { await app.addServer(account, token: pending.token) }
            }
        case let .failed(message):
            FailureStepView(message: message, onRetry: model.beginPlexLink)
        }
    }
}
