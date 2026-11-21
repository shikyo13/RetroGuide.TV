import RetroGuideKit
import SwiftUI

/// Hosts the onboarding steps with a shared header and background.
struct OnboardingFlowView: View {
    @Environment(AppModel.self) private var app
    @State private var model: OnboardingModel?
    @State private var selectedServers: [OnboardingModel.PendingServer] = []
    @State private var reviewingServers = false
    @State private var showsPro = false
    @State private var isStarting = false

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            BrandMark()
                .frame(maxWidth: .infinity, alignment: .leading)
            #if os(tvOS)
            Spacer(minLength: .zero)
            if reviewingServers {
                ScrollView { steps }
            } else {
                steps
            }
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
        .appSheet(isPresented: $showsPro) {
            NavigationStack {
                ProUpgradeView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsPro = false }
                        }
                    }
            }
        }
    }

    /// Each server's libraries lead to the ready screen, which adds another
    /// server or builds the channels.
    @ViewBuilder
    private var steps: some View {
        if reviewingServers {
            SetupReadyView(
                servers: selectedServers,
                canAddServer: app.pro.access.canAddServer(connectedCount: selectedServers.count),
                isStarting: isStarting,
                onRemove: remove,
                onAddServer: addAnotherServer,
                onShowPro: { showsPro = true },
                onBuild: build
            )
        } else if let model {
            ServerSetupStepsView(model: model, onCancel: cancelServerSetup, libraryConfirmTitle: String(localized: "Continue")) { pending, selected in
                var account = pending.account
                account.selectedLibraryIDs = selected
                selectedServers.append(OnboardingModel.PendingServer(
                    account: account, token: pending.token, accountToken: pending.accountToken, libraries: pending.libraries
                ))
                reviewingServers = true
            }
            if !selectedServers.isEmpty {
                Button("Back to Selected Servers", action: cancelServerSetup)
                    .buttonStyle(.retro)
            }
        }
    }

    private func build() {
        guard !isStarting else { return }
        isStarting = true
        Task { await app.completeInitialSetup(selectedServers); isStarting = false }
    }

    private func addAnotherServer() {
        model?.cancel()
        model = OnboardingModel(
            identities: app.identities,
            accountToken: app.servers.plexAccountToken,
            excludedServerIDs: Set(selectedServers.map { $0.account.id }),
            showsWelcome: false,
            onPlexAccountTokenChanged: app.servers.savePlexAccountToken
        )
        reviewingServers = false
    }

    /// Removing the last server starts setup over.
    private func remove(_ serverID: String) {
        selectedServers.removeAll { $0.account.id == serverID }
        guard selectedServers.isEmpty else { return }
        model?.cancel()
        model = OnboardingModel(identities: app.identities, accountToken: app.servers.plexAccountToken,
            onPlexAccountTokenChanged: app.servers.savePlexAccountToken)
        reviewingServers = false
    }

    private func cancelServerSetup() {
        model?.cancel()
        if !selectedServers.isEmpty { reviewingServers = true }
    }
}
