import Foundation
import Observation
import RetroGuideKit

/// Commercial sources are loaded separately and never added to the channel index.
@MainActor @Observable
final class CommercialLibrary {
    private(set) var items: [MediaItem] = []
    private(set) var allowedIDs: Set<String> = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    @ObservationIgnored private var snapshots: [LibrarySnapshot] = []
    @ObservationIgnored private var generation = 0
    private struct LoadKey: Equatable {
        let isEnabled: Bool
        let libraryIDs: Set<String>
        let accounts: [ServerAccount]
    }
    @ObservationIgnored private var loadedKey: LoadKey?

    func load(settings: CommercialBreakSettings, servers: ServerLibrary, force: Bool = false) async {
        await load(settings: settings, accounts: servers.accounts, clientProvider: servers.client, force: force)
    }

    func load(settings: CommercialBreakSettings, accounts: [ServerAccount], clientProvider: (String) -> (any MediaServerClient)?, force: Bool = false) async {
        let key = LoadKey(isEnabled: settings.isEnabled, libraryIDs: settings.libraryIDs, accounts: accounts)
        guard force || key != loadedKey else { return }
        generation += 1
        let token = generation
        loadedKey = nil
        defer { if token == generation { isLoading = false } }
        items = []; allowedIDs = []; snapshots = []; errorMessage = nil
        guard settings.isEnabled, !settings.libraryIDs.isEmpty else { loadedKey = key; isLoading = false; return }
        isLoading = true
        var loaded: [LibrarySnapshot] = []
        for account in accounts {
            guard settings.libraryIDs.contains(where: { $0.hasPrefix(account.id + "/") }) else { continue }
            let remaining = max(CommercialBreakPlan.Limits.maximumCatalogItems - loaded.reduce(0) { $0 + $1.items.count }, 0)
            guard remaining > .zero else { break }
            do {
                try Task.checkCancellation()
                guard let client = clientProvider(account.id) else { throw StreamError.serverUnreachable }
                let libraries = try await client.fetchLibraries().filter { settings.libraryIDs.contains($0.id) && $0.isSchedulable }
                guard token == generation, !Task.isCancelled else { return }
                guard !libraries.isEmpty else { continue }
                let fetched = try await client.fetchItems(in: libraries, limit: remaining, progress: { _ in })
                guard token == generation, !Task.isCancelled else { return }
                let clips = Array(fetched.lazy.filter(CommercialBreakPlan.eligible).prefix(remaining))
                loaded.append(LibrarySnapshot(serverID: account.id, serverName: account.name, libraries: libraries, items: clips))
            } catch {
                guard token == generation, !Task.isCancelled else { return }
                errorMessage = "Some commercial libraries could not be loaded. Programs will continue on schedule."
            }
        }
        guard token == generation, !Task.isCancelled else { return }
        loadedKey = errorMessage == nil ? key : nil
        snapshots = loaded
        isLoading = false
    }
    func apply(policy: ParentalPolicy, servers: ServerLibrary) {
        apply(policy: policy, activeServerIDs: Set(servers.accounts.filter { servers.status[$0.id] != .offline }.map(\.id)))
    }

    func apply(policy: ParentalPolicy, activeServerIDs: Set<String>) {
        let active = snapshots.filter { activeServerIDs.contains($0.serverID) }
        let filtered = policy.filtering(active)
        // Merge only eligible copies, using the same identities as regular libraries.
        items = LibraryIndex(snapshots: filtered).items
        allowedIDs = Set(items.map(\.id))
    }
}
