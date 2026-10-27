import RetroGuideKit

struct ParentalContentChoices: Sendable {
    let libraries: [FacetOption]
    let genres: [FacetOption]
    let collections: [FacetOption]
    let catalog: ParentalTitleCatalog

    init(snapshots: [LibrarySnapshot], accounts: [ServerAccount]) {
        let labels = Dictionary(accounts.map { account in
            let name = "\(account.name) · \(account.kind.displayName)"
            let duplicates = accounts.filter { $0.name == account.name && $0.kind == account.kind }
            let label = duplicates.count > 1 ? "\(name) · \(ServerAddressText.short(account.baseURL))" : name
            return (account.id, label)
        }, uniquingKeysWith: { first, _ in first })
        let snapshots = snapshots.map { snapshot in
            LibrarySnapshot(serverID: snapshot.serverID, serverName: labels[snapshot.serverID] ?? snapshot.serverName,
                libraries: snapshot.libraries, items: snapshot.items, refreshedAt: snapshot.refreshedAt)
        }
        libraries = snapshots.flatMap { snapshot in
            snapshot.libraries.map { FacetOption(id: $0.id, title: $0.title, detail: snapshot.serverName) }
        }.sorted { ($0.title, $0.detail ?? "", $0.id) < ($1.title, $1.detail ?? "", $1.id) }
        let names = Set(snapshots.flatMap { $0.items.flatMap(\.collections) }).sorted()
        var seen: Set<String> = []
        collections = names.compactMap { name in
            let key = ParentalPolicy.collectionKey(name)
            guard seen.insert(key).inserted else { return nil }
            return FacetOption(id: key, title: name, detail: nil)
        }
        seen.removeAll()
        genres = Set(snapshots.flatMap { $0.items.flatMap(\.genres) }).sorted().compactMap { name in
            let key = ParentalPolicy.genreKey(name)
            guard !key.isEmpty, seen.insert(key).inserted else { return nil }
            return FacetOption(id: key, title: name, detail: nil)
        }
        catalog = ParentalTitleCatalog(snapshots: snapshots)
    }
}
