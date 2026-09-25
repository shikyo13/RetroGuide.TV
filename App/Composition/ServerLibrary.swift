import Foundation
import Observation
import RetroGuideKit

/// All connected media servers: their accounts, cached library snapshots,
/// reachability, and parallel indexing. Servers are kept in priority order;
/// when the same title exists on several servers, the first one wins.
@MainActor
@Observable
final class ServerLibrary {
    enum Status: Equatable {
        case online
        case offline
    }

    private enum KeychainAccount {
        /// The Plex account token, kept so more servers can be added without re-linking.
        static let plexAccount = "plex.account"
    }

    private(set) var accounts: [ServerAccount] = []
    private(set) var status: [String: Status] = [:]
    private(set) var artworkResolver = ArtworkResolver.unavailable

    @ObservationIgnored private let store: PreferencesStore
    @ObservationIgnored private let snapshotStore: LibrarySnapshotStore
    @ObservationIgnored private let keychain: KeychainStore
    @ObservationIgnored private let registry: ServerRegistry
    @ObservationIgnored private let identity: PlexClientIdentity
    @ObservationIgnored private var snapshots: [String: LibrarySnapshot] = [:]

    init(store: PreferencesStore, snapshotStore: LibrarySnapshotStore, keychain: KeychainStore, identity: PlexClientIdentity) {
        self.store = store
        self.snapshotStore = snapshotStore
        self.keychain = keychain
        self.identity = identity
        self.registry = ServerRegistry(keychain: keychain, plexIdentity: identity)
    }

    // MARK: - Queries

    var hasServers: Bool {
        !accounts.isEmpty
    }

    var plexAccountToken: String? {
        keychain.token(for: KeychainAccount.plexAccount)
    }

    func client(for serverID: String) -> (any MediaServerClient)? {
        registry.client(for: serverID)
    }

    /// Snapshots of reachable servers, in priority order.
    var activeSnapshots: [LibrarySnapshot] {
        accounts.compactMap { account in
            status[account.id] == .offline ? nil : snapshots[account.id]
        }
    }

    /// When the oldest cached library was indexed, or `nil` if any server has no cache.
    var oldestRefresh: Date? {
        let dates = accounts.map { snapshots[$0.id]?.refreshedAt }
        guard !dates.isEmpty, !dates.contains(where: { $0 == nil }) else { return nil }
        return dates.compactMap { $0 }.min()
    }

    func libraries(forServer serverID: String) async throws -> [MediaLibrary] {
        guard let client = registry.client(for: serverID) else { return [] }
        return try await client.fetchLibraries().filter(\.isSchedulable)
    }

    // MARK: - Lifecycle

    /// Reconnects saved servers and loads their cached libraries.
    func restore() async {
        accounts = store.accounts
        let missingTokens = registry.connect(accounts)
        accounts.removeAll { account in missingTokens.contains { $0.id == account.id } }
        artworkResolver = registry.artworkResolver
        for account in accounts {
            if let snapshot = await snapshotStore.load(serverID: account.id) {
                snapshots[account.id] = snapshot
            }
        }
    }

    func add(_ account: ServerAccount, token: String, accountToken: String?) {
        if let accountToken {
            keychain.setToken(accountToken, for: KeychainAccount.plexAccount)
        }
        registry.add(account, token: token)
        artworkResolver = registry.artworkResolver
        accounts.removeAll { $0.id == account.id }
        accounts.append(account)
        status[account.id] = .online
        store.accounts = accounts
    }

    func remove(serverID: String) {
        registry.remove(serverID: serverID)
        snapshotStore.remove(serverID: serverID)
        snapshots[serverID] = nil
        status[serverID] = nil
        accounts.removeAll { $0.id == serverID }
        artworkResolver = registry.artworkResolver
        store.accounts = accounts
    }

    func setSelectedLibraries(_ libraryIDs: Set<String>, serverID: String) {
        guard let index = accounts.firstIndex(where: { $0.id == serverID }) else { return }
        accounts[index].selectedLibraryIDs = libraryIDs
        store.accounts = accounts
    }

    func removeAll() {
        accounts.map(\.id).forEach(remove(serverID:))
        keychain.removeToken(for: KeychainAccount.plexAccount)
    }

    // MARK: - Indexing

    /// Re-indexes every server in parallel. A server that fails is marked
    /// offline (its cached library, if any, is set aside); this only throws
    /// when no server could be indexed at all.
    func refreshAll(progress: @escaping @MainActor (LibraryLoadProgress) -> Void) async throws {
        let accounts = accounts
        let aggregator = ProgressAggregator(serverCount: accounts.count, report: progress)
        var failures: [Error] = []
        await withTaskGroup(of: (ServerAccount, Result<LibrarySnapshot, Error>).self) { group in
            for account in accounts {
                guard let client = registry.client(for: account.id) else { continue }
                group.addTask {
                    do {
                        let snapshot = try await Self.download(account, client: client) { update in
                            Task { @MainActor in aggregator.update(serverID: account.id, with: update) }
                        }
                        return (account, .success(snapshot))
                    } catch {
                        return (account, .failure(error))
                    }
                }
            }
            for await (account, result) in group {
                switch result {
                case let .success(snapshot):
                    snapshots[account.id] = snapshot
                    status[account.id] = .online
                    await snapshotStore.save(snapshot)
                case let .failure(error):
                    status[account.id] = .offline
                    failures.append(error)
                }
            }
        }
        if let failure = failures.first, failures.count == accounts.count {
            throw failure
        }
    }

    private nonisolated static func download(
        _ account: ServerAccount,
        client: any MediaServerClient,
        progress: @escaping @Sendable (LibraryLoadProgress) -> Void
    ) async throws -> LibrarySnapshot {
        let libraries = try await client.fetchLibraries().filter {
            $0.isSchedulable && (account.selectedLibraryIDs.isEmpty || account.selectedLibraryIDs.contains($0.id))
        }
        let items = try await client.fetchItems(in: libraries, progress: progress)
        return LibrarySnapshot(serverID: account.id, serverName: account.name, libraries: libraries, items: items)
    }

    // MARK: - Reachability

    /// Probes every server. Unreachable Plex servers are re-located through the
    /// Plex account (their address may have changed). Returns whether any
    /// server's availability changed.
    @discardableResult
    func checkReachability() async -> Bool {
        var changed = false
        for account in accounts {
            let reachable = await isReachable(account)
            let newStatus: Status = reachable ? .online : .offline
            if status[account.id] != newStatus {
                status[account.id] = newStatus
                changed = true
            }
        }
        return changed
    }

    private func isReachable(_ account: ServerAccount) async -> Bool {
        if let client = registry.client(for: account.id), await client.isReachable() {
            return true
        }
        guard account.kind == .plex, let newURL = await relocatePlexServer(account.id) else { return false }
        var updated = account
        updated.baseURL = newURL
        registry.updateAddress(of: updated)
        artworkResolver = registry.artworkResolver
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = updated
            store.accounts = accounts
        }
        return await registry.client(for: account.id)?.isReachable() ?? false
    }

    private func relocatePlexServer(_ serverID: String) async -> URL? {
        guard let accountToken = plexAccountToken,
              let candidate = try? await PlexAccountService(identity: identity)
                  .servers(accountToken: accountToken)
                  .first(where: { $0.id == serverID })
        else { return nil }
        return try? await PlexConnectionResolver(identity: identity).resolve(candidate)
    }
}

/// Combines per-server indexing progress into one overall progress value.
@MainActor
private final class ProgressAggregator {
    private let serverCount: Int
    private let report: @MainActor (LibraryLoadProgress) -> Void
    private var fractions: [String: Double] = [:]

    init(serverCount: Int, report: @escaping @MainActor (LibraryLoadProgress) -> Void) {
        self.serverCount = max(serverCount, 1)
        self.report = report
    }

    func update(serverID: String, with progress: LibraryLoadProgress) {
        fractions[serverID] = progress.fraction
        let overall = fractions.values.reduce(.zero, +) / Double(serverCount)
        report(LibraryLoadProgress(fraction: overall, message: progress.message))
    }
}
