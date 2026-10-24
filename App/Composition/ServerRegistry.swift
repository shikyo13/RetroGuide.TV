import Foundation
import RetroGuideKit

/// Builds and holds one `MediaServerClient` per connected server.
@MainActor
final class ServerRegistry {
    private var clients: [String: any MediaServerClient] = [:]
    private let keychain: KeychainStore
    private let identities: ServerIdentities

    init(keychain: KeychainStore, identities: ServerIdentities) {
        self.keychain = keychain
        self.identities = identities
    }

    func client(for serverID: String) -> (any MediaServerClient)? {
        clients[serverID]
    }

    /// Creates clients for accounts whose tokens are in the keychain.
    /// Returns the accounts that could not be restored (missing token).
    @discardableResult
    func connect(_ accounts: [ServerAccount]) -> [ServerAccount] {
        var missing: [ServerAccount] = []
        for account in accounts {
            guard let token = keychain.token(for: account.id) else {
                missing.append(account)
                continue
            }
            clients[account.id] = makeClient(for: account, token: token)
        }
        return missing
    }

    func add(_ account: ServerAccount, token: String) {
        keychain.setToken(token, for: account.id)
        clients[account.id] = makeClient(for: account, token: token)
    }

    /// Rebuilds a server's client after its address or settings changed, reusing the stored token.
    func refreshClient(for account: ServerAccount) {
        guard let token = keychain.token(for: account.id) else { return }
        clients[account.id] = makeClient(for: account, token: token)
    }

    func remove(serverID: String) {
        keychain.removeToken(for: serverID)
        clients[serverID] = nil
    }

    /// A value-type resolver capturing the current clients, safe to hand to views.
    var artworkResolver: ArtworkResolver {
        let snapshot = clients
        return ArtworkResolver { serverID, reference, size in
            snapshot[serverID]?.imageURL(for: reference, size: size)
        }
    }

    private func makeClient(for account: ServerAccount, token: String) -> any MediaServerClient {
        #if DEBUG
        if let demo = DebugBootstrap.demoClient(for: account) {
            return demo
        }
        #endif
        return switch account.kind {
        case .plex:
            PlexServerClient(
                serverID: account.id,
                baseURL: account.baseURL,
                token: token,
                identity: identities.plex,
                playback: account.playback
            )
        case .jellyfin:
            JellyfinServerClient(
                serverID: account.id,
                baseURL: account.baseURL,
                token: token,
                userID: account.userID ?? "",
                identity: identities.jellyfin,
                playback: account.playback
            )
        }
    }
}
