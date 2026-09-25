import RetroGuideKit
import SwiftUI

/// Adds another server, reusing the onboarding steps. With a saved Plex account
/// it goes straight to the server list; otherwise it shows a link code first.
struct AddServerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: OnboardingModel?

    var body: some View {
        VStack {
            if let model {
                ServerSetupStepsView(model: model, onCancel: { dismiss() }) { pending, selected in
                    var account = pending.account
                    account.selectedLibraryIDs = selected
                    dismiss()
                    Task { await app.addServer(account, token: pending.token, accountToken: pending.accountToken) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .crtEffect()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard model == nil else { return }
            let setup = OnboardingModel(
                identity: app.plexIdentity,
                accountToken: app.servers.plexAccountToken,
                excludedServerIDs: Set(app.servers.accounts.map(\.id))
            )
            model = setup
            setup.begin()
        }
    }
}
