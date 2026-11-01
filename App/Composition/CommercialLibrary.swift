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
    @ObservationIgnored private var loadedKey: String?

    func load(settings: CommercialBreakSettings, servers: ServerLibrary, force: Bool = false) async {
        let key = "\(settings.isEnabled)/\(settings.libraryIDs.sorted())/\(servers.accounts.map(\.id).sorted())"
        guard force || key != loadedKey else { return }
        generation += 1
        let token = generation
        items = []; allowedIDs = []; snapshots = []; errorMessage = nil
        guard settings.isEnabled, !settings.libraryIDs.isEmpty else { loadedKey = key; isLoading = false; return }
        isLoading = true
        var loaded: [LibrarySnapshot] = []
        for account in servers.accounts {
            guard settings.libraryIDs.contains(where: { $0.hasPrefix(account.id + "/") }),
                  let client = servers.client(for: account.id) else { continue }
            do {
                let libraries = try await client.fetchLibraries().filter { settings.libraryIDs.contains($0.id) && $0.isSchedulable }
                guard !libraries.isEmpty else { continue }
                let fetched = try await client.fetchItems(in: libraries, progress: { _ in })
                guard token == generation, !Task.isCancelled else { return }
                let remaining = max(CommercialBreakPlan.Limits.maximumCatalogItems - loaded.reduce(0) { $0 + $1.items.count }, 0)
                let clips = Array(fetched.lazy.filter(CommercialBreakPlan.eligible).prefix(remaining))
                loaded.append(LibrarySnapshot(serverID: account.id, serverName: account.name, libraries: libraries, items: clips))
            } catch {
                guard token == generation else { return }
                errorMessage = "Some commercial libraries could not be loaded. Programs will continue on schedule."
            }
        }
        guard token == generation, !Task.isCancelled else { return }
        loadedKey = key
        snapshots = loaded
        isLoading = false
    }
    func apply(policy: ParentalPolicy, servers: ServerLibrary) {
        let active = snapshots.filter { snapshot in servers.accounts.contains { $0.id == snapshot.serverID } && servers.status[snapshot.serverID] != .offline }
        let filtered = policy.filtering(active)
        // Merge only eligible copies, using the same identities as regular libraries.
        items = LibraryIndex(snapshots: filtered).items
        allowedIDs = Set(items.map(\.id))
    }
}
