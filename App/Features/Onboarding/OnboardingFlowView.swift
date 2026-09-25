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
            Spacer(minLength: .zero)
            if let model {
                ServerSetupStepsView(model: model, onCancel: model.cancel) { pending, selected in
                    var account = pending.account
                    account.selectedLibraryIDs = selected
                    Task { await app.addServer(account, token: pending.token, accountToken: pending.accountToken) }
                }
            }
            Spacer(minLength: .zero)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .crtEffect()
        .onAppear {
            if model == nil {
                model = OnboardingModel(identity: app.plexIdentity)
            }
        }
    }
}
