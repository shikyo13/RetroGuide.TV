import SwiftUI

/// Switches between the app's top-level phases.
struct RootView: View {
    @Environment(AppModel.self) private var model

    @State private var showsStartupSettings = false

    private var startupActionTitle: String {
        switch model.phase {
        case .launching, .indexing: "Cancel Channel Loading"
        default: "Manage Servers and Libraries"
        }
    }

    var body: some View {
        ZStack {
            if model.isApplyingParentalControls {
                ProgressView("Applying parental controls…")
            } else {
                switch model.phase {
                case .launching:
                    SplashView()
                case .onboarding:
                    OnboardingFlowView()
                case let .indexing(progress):
                    IndexingView(progress: progress)
                case .ready:
                    if model.parentalControls.policy.isEnabled && model.visibleChannels.isEmpty {
                        ParentalEmptyView()
                    } else {
                        WatchView()
                    }
                case let .failed(message):
                    FailureView(message: message, isCancelled: model.isManagingStartup) {
                        Task { await model.retryAfterFailure() }
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if model.phase != .ready && model.phase != .onboarding && model.servers.hasServers {
                Button(startupActionTitle) {
                    switch model.phase {
                    case .launching, .indexing:
                        model.cancelStartup()
                    default:
                        model.manageStartup()
                        showsStartupSettings = true
                    }
                }
                .buttonStyle(.retro)
                .padding(DesignTokens.Spacing.xl)
            }
        }
        .sheet(isPresented: $showsStartupSettings) {
            ParentalSettingsGate {
                NavigationStack {
                    ServersView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showsStartupSettings = false }
                            }
                        }
                }
            }
        }
        .animation(DesignTokens.Motion.relaxedEase, value: model.phase)
        .onOpenURL { url in
            model.open(url)
        }
        #if os(tvOS)
        .routeRemoteCommands()
        #endif
        .onChange(of: model.homeScreenTheme, initial: true) {
            model.applyHomeScreenTheme()
        }
    }
}
