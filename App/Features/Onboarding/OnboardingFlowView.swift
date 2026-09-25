import RetroGuideKit
import SwiftUI

/// Hosts the onboarding steps with a shared header and background.
struct OnboardingFlowView: View {
    @Environment(AppModel.self) private var app
    @State private var model: OnboardingModel?

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
                model = OnboardingModel(identity: app.plexIdentity)
            }
        }
    }

    @ViewBuilder
    private var steps: some View {
        if let model {
            ServerSetupStepsView(model: model, onCancel: model.cancel) { pending, selected in
                var account = pending.account
                account.selectedLibraryIDs = selected
                Task { await app.addServer(account, token: pending.token, accountToken: pending.accountToken) }
            }
        }
    }
}
