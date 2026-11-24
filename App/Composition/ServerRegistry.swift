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
    /// Returns the accounts whose token is gone. One the keychain can't read
    /// right now is neither connected nor returned: ``reconnect(_:)`` tries again.
    @discardableResult
    func connect(_ accounts: [ServerAccount]) -> [ServerAccount] {
        var missing: [ServerAccount] = []
        for account in accounts {
            switch keychain.lookUpToken(for: account.id) {
            case let .found(token): clients[account.id] = makeClient(for: account, token: token)
            case .missing: missing.append(account)
            case .unavailable: break
            }
        }
        return missing
    }

    /// Connects a server that has no client yet because its token couldn't be read
    /// earlier. Whether it now has one.
    @discardableResult
    func reconnect(_ account: ServerAccount) -> Bool {
        guard clients[account.id] == nil else { return true }
        guard case let .found(token) = keychain.lookUpToken(for: account.id) else { return false }
        clients[account.id] = makeClient(for: account, token: token)
        return true
    }

    /// Saves the server's token and connects it; `false` (and nothing added) when
    /// the keychain wouldn't save it, since the server would be lost on restart.
    func add(_ account: ServerAccount, token: String) -> Bool {
        guard keychain.setToken(token, for: account.id) else { return false }
        clients[account.id] = makeClient(for: account, token: token)
        return true
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
