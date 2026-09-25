#if DEBUG
import Foundation
import RetroGuideKit

/// Development convenience: seeds a Plex account from environment variables so
/// the simulator can be pointed at a server without going through onboarding.
///
/// Variables (set in the Xcode scheme or by a launch script, never committed):
/// `RETROGUIDE_DEV_PLEX_URL`, `RETROGUIDE_DEV_PLEX_TOKEN`, `RETROGUIDE_DEV_PLEX_SERVER_ID`,
/// `RETROGUIDE_DEV_PLEX_SERVER_NAME`, and optionally `RETROGUIDE_DEV_RESET=1`.
enum DebugBootstrap {
    private enum Variable {
        static let url = "RETROGUIDE_DEV_PLEX_URL"
        static let token = "RETROGUIDE_DEV_PLEX_TOKEN"
        static let serverID = "RETROGUIDE_DEV_PLEX_SERVER_ID"
        static let serverName = "RETROGUIDE_DEV_PLEX_SERVER_NAME"
        static let reset = "RETROGUIDE_DEV_RESET"
    }

    @MainActor
    static func seedAccountIfRequested(store: PreferencesStore, keychain: KeychainStore, identity: PlexClientIdentity) async {
        let environment = ProcessInfo.processInfo.environment
        if environment[Variable.reset] == "1" {
            store.accounts.forEach { keychain.removeToken(for: $0.id) }
            store.resetAll()
        }
        guard store.accounts.isEmpty,
              let urlString = environment[Variable.url], let url = URL(string: urlString),
              let token = environment[Variable.token],
              let serverID = environment[Variable.serverID]
        else { return }
        let account = ServerAccount(
            id: serverID,
            kind: .plex,
            name: environment[Variable.serverName] ?? "Plex",
            baseURL: url
        )
        keychain.setToken(token, for: serverID)
        store.accounts = [account]
    }
}
#endif
