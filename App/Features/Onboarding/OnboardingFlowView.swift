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
    @Environment(\.theme) private var theme

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
        .sheet(isPresented: $showsPro) {
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

    @ViewBuilder
    private var steps: some View {
        if reviewingServers {
            serverSummary
        } else if let model {
            ServerSetupStepsView(model: model, onCancel: cancelServerSetup, libraryConfirmTitle: "Continue") { pending, selected in
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

    private var serverSummary: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text("Your servers")
                .font(Typography.title)
                .foregroundStyle(theme.textPrimary)
            Text("Add the servers you want, then build your channels. Programs from all selected servers appear in one guide.")
                .font(Typography.body)
                .foregroundStyle(theme.textSecondary)
            ForEach(selectedServers, id: \.account.id) { selection in
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    Text(selection.account.name)
                        .font(Typography.headline)
                        .foregroundStyle(theme.textPrimary)
                    Text(selection.libraries.filter { selection.account.selectedLibraryIDs.contains($0.id) }.map(\.title).joined(separator: ", "))
                        .font(Typography.callout)
                        .foregroundStyle(theme.textSecondary)
                    Button("Remove \(selection.account.name)") {
                        selectedServers.removeAll { $0.account.id == selection.account.id }
                    }
                    .buttonStyle(.retro)
                }
            }
            if app.pro.access.canAddServer(connectedCount: selectedServers.count) {
                Button("Add Another Server") {
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
                .buttonStyle(.retro)
            } else {
                Button("Connect Multiple Servers with Pro") { showsPro = true }
                    .buttonStyle(.retro)
            }
            Button("Build My Channels") {
                isStarting = true
                Task { await app.completeInitialSetup(selectedServers); isStarting = false }
            }
            .buttonStyle(.retroPrimary)
            .disabled(selectedServers.isEmpty || isStarting ||
                (selectedServers.count > 1 && !app.pro.access.canAddServer(connectedCount: selectedServers.count - 1)))
        }
        .disabled(isStarting)
    }

    private func cancelServerSetup() {
        model?.cancel()
        if !selectedServers.isEmpty { reviewingServers = true }
    }
}
