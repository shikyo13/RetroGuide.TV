#if DEBUG
import Foundation
import RetroGuideKit

/// Development convenience: seeds a Plex account from environment variables so
/// the simulator can be pointed at a server without going through onboarding.
///
/// Variables (set in the Xcode scheme or by a launch script, never committed):
/// `RETROGUIDE_DEV_PLEX_URL`, `RETROGUIDE_DEV_PLEX_TOKEN`, `RETROGUIDE_DEV_PLEX_SERVER_ID`,
/// `RETROGUIDE_DEV_PLEX_SERVER_NAME`, optionally `RETROGUIDE_DEV_PLEX_ACCOUNT_TOKEN`
/// (enables "Add a server" without linking) and `RETROGUIDE_DEV_RESET=1`.
///
/// `RETROGUIDE_DEMO_LIBRARY` (a ``DemoCatalog`` JSON file) connects the demo
/// library instead of a real server, for screenshots. `RETROGUIDE_DEV_THEME`
/// (a ``ThemeID`` raw value) picks the theme.
enum DebugBootstrap {
    private enum Variable {
        static let url = "RETROGUIDE_DEV_PLEX_URL"
        static let token = "RETROGUIDE_DEV_PLEX_TOKEN"
        static let serverID = "RETROGUIDE_DEV_PLEX_SERVER_ID"
        static let serverName = "RETROGUIDE_DEV_PLEX_SERVER_NAME"
        static let accountToken = "RETROGUIDE_DEV_PLEX_ACCOUNT_TOKEN"
        static let reset = "RETROGUIDE_DEV_RESET"
        static let demoLibrary = "RETROGUIDE_DEMO_LIBRARY"
        static let theme = "RETROGUIDE_DEV_THEME"
    }

    /// Stands in for the keychain token of the demo server, which needs none.
    private static let demoToken = "demo"

    @MainActor
    static func seedAccountIfRequested(store: PreferencesStore, keychain: KeychainStore, identity: PlexClientIdentity) async {
        let environment = ProcessInfo.processInfo.environment
        if environment[Variable.reset] == "1" {
            store.accounts.forEach { keychain.removeToken(for: $0.id) }
            store.resetAll()
            keychain.removeToken(for: ServerLibrary.KeychainAccount.plexAccount)
        }
        if let theme = environment[Variable.theme].flatMap(ThemeID.init(rawValue:)) {
            store.preferences.themeID = theme
        }
        if let accountToken = environment[Variable.accountToken], keychain.token(for: ServerLibrary.KeychainAccount.plexAccount) == nil {
            keychain.setToken(accountToken, for: ServerLibrary.KeychainAccount.plexAccount)
        }
        if store.accounts.isEmpty, let path = environment[Variable.demoLibrary] {
            seedDemoAccount(catalogURL: URL(fileURLWithPath: path), store: store, keychain: keychain)
            return
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

    /// The demo library's client, when `account` points at a demo catalog file.
    static func demoClient(for account: ServerAccount) -> (any MediaServerClient)? {
        guard account.baseURL.isFileURL, let catalog = DemoCatalog.load(from: account.baseURL) else { return nil }
        return DemoServerClient(catalog: catalog)
    }

    @MainActor
    private static func seedDemoAccount(catalogURL: URL, store: PreferencesStore, keychain: KeychainStore) {
        guard let catalog = DemoCatalog.load(from: catalogURL) else { return }
        let account = ServerAccount(id: catalog.server.id, kind: .plex, name: catalog.server.name, baseURL: catalogURL)
        keychain.setToken(demoToken, for: account.id)
        store.accounts = [account]
    }
}
#endif
