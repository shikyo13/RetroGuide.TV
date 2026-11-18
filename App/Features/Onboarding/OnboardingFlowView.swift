import RetroGuideKit
import SwiftUI

/// Hosts the onboarding steps with a shared header and background.
struct OnboardingFlowView: View {
    @Environment(AppModel.self) private var app
    @State private var model: OnboardingModel?
    @State private var isStarting = false

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            BrandMark()
                .frame(maxWidth: .infinity, alignment: .leading)
            #if os(tvOS)
            Spacer(minLength: .zero)
            steps
            Spacer(minLength: .zero)
            #else
            // Centered, but scrolls when a step doesn't fit (a phone in landscape).
            GeometryReader { proxy in
                ScrollView {
                    steps
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            #endif
        }
        .padding(.horizontal, PlatformMetric.value(tv: .zero, touch: DesignTokens.Spacing.md))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .crtEffect()
        .onAppear {
            if model == nil {
                model = OnboardingModel(identities: app.identities, accountToken: app.servers.plexAccountToken,
                    onPlexAccountTokenChanged: app.servers.savePlexAccountToken)
            }
        }
        .onDisappear { model?.cancel() }
    }

    /// Choosing the libraries builds the channels; more servers can be added
    /// later in Settings.
    @ViewBuilder
    private var steps: some View {
        if let model {
            ServerSetupStepsView(model: model, onCancel: { model.cancel() }) { pending, selected in
                guard !isStarting else { return }
                var account = pending.account
                account.selectedLibraryIDs = selected
                let selection = OnboardingModel.PendingServer(
                    account: account, token: pending.token, accountToken: pending.accountToken, libraries: pending.libraries
                )
                isStarting = true
                Task { await app.completeInitialSetup([selection]); isStarting = false }
            }
            .disabled(isStarting)
        }
    }
}
