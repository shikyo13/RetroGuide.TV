import RetroGuideKit
import SwiftUI

/// The steps of connecting a server (choose Plex or Jellyfin, sign in, choose
/// server, choose libraries), shared by first-run onboarding and "Add a server" in Settings.
struct ServerSetupStepsView: View {
    let model: OnboardingModel
    let onCancel: () -> Void
    var libraryConfirmTitle = "Build My Channels"
    let onComplete: (OnboardingModel.PendingServer, Set<String>) -> Void

    var body: some View {
        Group {
            switch model.step {
            case .welcome:
                WelcomeStepView(onPlex: model.beginPlex, onJellyfin: model.beginJellyfin)
            case .choosingKind:
                ServerKindStepView(onPlex: model.beginPlex, onJellyfin: model.beginJellyfin, onCancel: onCancel)
            case let .linking(code):
                PlexLinkStepView(
                    code: code,
                    signIn: model.plexSignIn,
                    onSwitchSignIn: model.switchPlexSignIn,
                    onCancel: onCancel
                )
            case let .choosingServer(servers, accountHasServers):
                ServerPickerStepView(
                    servers: servers,
                    accountHasServers: accountHasServers,
                    onChoose: model.choose,
                    onAnotherAccount: model.useAnotherPlexAccount,
                    onJellyfin: model.beginJellyfin,
                    onCancel: onCancel
                )
            case let .findingJellyfin(scan, isSearching):
                JellyfinFindStepView(
                    scan: scan,
                    isSearching: isSearching,
                    onChoose: model.chooseJellyfin,
                    onSearchAgain: model.findJellyfinServers,
                    onEnterAddress: model.enterJellyfinAddress,
                    onCancel: onCancel
                )
            case let .enteringJellyfinAddress(message):
                JellyfinAddressStepView(
                    address: model.lastJellyfinAddress,
                    message: message,
                    onConnect: model.connectToJellyfin,
                    onBack: model.beginJellyfin
                )
            case let .jellyfinSignIn(signIn):
                JellyfinSignInStepView(
                    signIn: signIn,
                    onSignIn: model.signInToJellyfin,
                    onUsePassword: model.useJellyfinPassword,
                    onUseQuickConnect: model.useJellyfinQuickConnect,
                    onCancel: onCancel
                )
            case let .connecting(name):
                ConnectingStepView(serverName: name)
            case let .choosingLibraries(pending):
                LibraryPickerView(libraries: pending.libraries, confirmTitle: libraryConfirmTitle) { selected in
                    onComplete(pending, selected)
                }
            case let .failed(message):
                FailureStepView(message: message, onRetry: model.retry)
            }
        }
        .transition(.opacity)
        .animation(DesignTokens.Motion.standardEase, value: model.step)
    }
}
