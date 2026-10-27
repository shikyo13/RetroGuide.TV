import Foundation
import RetroGuideKit

/// The parental policy as Settings › Parental Controls edits it. Titles are
/// catalog ids; custom-lineup channels are editor drafts.
struct ParentalDraft: Codable, Sendable {
    let isEnabled: Bool
    let usesCustomLineup: Bool
    let customChannels: [ChannelDraft]
    let maximumMovieRating: String
    let maximumTVRating: String
    let allowsUnrated: Bool
    let allLibraries: Bool
    let libraryIDs: [String]
    let allGenres: Bool
    let genreNames: [String]
    let selectedContentOnly: Bool
    let collectionNames: [String]
    let allowedTitleIDs: [String]
    let blockedTitleIDs: [String]
}

/// The draft of the saved policy and everything it can choose from.
struct ParentalEditor: Encodable, Sendable {
    let draft: ParentalDraft
    let movieRatings: [String]
    let tvRatings: [String]
    let libraries: [FacetOptionInfo]
    let genres: [FacetOptionInfo]
    let collections: [FacetOptionInfo]
    let titles: [FacetOptionInfo]
}

struct ParentalChannelParams: Decodable, Sendable {
    let channel: ChannelDraft
    let policy: ParentalDraft
}

struct ParentalStatus: Encodable, Sendable {
    let isEnabled: Bool
    let usesCustomLineup: Bool
}

struct LockedParams: Decodable, Sendable {
    let isLocked: Bool
}

enum ParentalError: LocalizedError {
    case restricted

    var errorDescription: String? {
        "This program is restricted by parental controls."
    }
}

extension CoreState {
    /// Prefix for saved titles no longer in any library (kept so they stay chosen).
    private static let savedTitlePrefix = "saved/"

    func parentalStatus() -> ParentalStatus {
        ParentalStatus(isEnabled: parentalPolicy.isEnabled, usesCustomLineup: parentalPolicy.usesCustomLineup)
    }

    /// Settings are locked until the parent enters the PIN (the app tracks the PIN).
    func setParentalLocked(_ params: LockedParams) -> Done {
        isParentalLocked = params.isLocked
        return Done()
    }

    /// The snapshots the lineup is built from: everything, or what the policy allows.
    var allowedSnapshots: [LibrarySnapshot] {
        let active = accounts.compactMap { snapshots[$0.id] }.filter { !offlineServerIDs.contains($0.serverID) }
        return parentalPolicy.filtering(active)
    }

    /// Whether `item` may play now (the policy may have changed since the lineup was built).
    func checkParental(_ item: MediaItem) throws {
        guard !parentalPolicy.isEnabled || parentalAllowedItemIDs.contains(item.id) else { throw ParentalError.restricted }
    }

    func parentalEditor() -> ParentalEditor {
        let known = accounts.compactMap { snapshots[$0.id] }
        let catalog = ParentalTitleCatalog(snapshots: labeled(known))
        var policy = parentalPolicy.resolvingTitles(in: catalog)
        policy.collectionNames = Set(policy.collectionNames.map(ParentalPolicy.collectionKey))
        policy.genreNames = Set(policy.genreNames.map(ParentalPolicy.genreKey))
        let unavailableAllowed = policy.allowedTitles.filter { catalog.selectedIDs(for: [$0]).isEmpty }
        let unavailableBlocked = policy.blockedTitles.filter { catalog.selectedIDs(for: [$0], blocking: true).isEmpty }
        let draft = ParentalDraft(
            isEnabled: policy.isEnabled,
            usesCustomLineup: policy.usesCustomLineup,
            customChannels: policy.channelCustomization.customChannels.map(draft(of:)),
            maximumMovieRating: policy.maximumMovieRating.rawValue,
            maximumTVRating: policy.maximumTVRating.rawValue,
            allowsUnrated: policy.allowsUnrated,
            allLibraries: policy.allLibraries,
            libraryIDs: policy.libraryIDs.sorted(),
            allGenres: policy.allGenres,
            genreNames: policy.genreNames.sorted(),
            selectedContentOnly: policy.selectedContentOnly,
            collectionNames: policy.collectionNames.sorted(),
            allowedTitleIDs: catalog.selectedIDs(for: policy.allowedTitles).sorted() + unavailableAllowed.map(Self.savedID),
            blockedTitleIDs: catalog.selectedIDs(for: policy.blockedTitles, blocking: true).sorted() + unavailableBlocked.map(Self.savedID)
        )
        let titles = catalog.titles.map { title in
            FacetOptionInfo(id: title.id, title: title.name, detail: ([title.identity.kind == .movie ? "Movie" : "TV show"]
                + (title.year.map { [String($0)] } ?? []) + title.serverNames).joined(separator: " · "))
        } + (unavailableAllowed + unavailableBlocked).map { FacetOptionInfo(id: Self.savedID($0), title: $0.name, detail: "Currently unavailable") }
        return ParentalEditor(
            draft: draft,
            movieRatings: ParentalPolicy.MovieRating.allCases.map(\.rawValue),
            tvRatings: ParentalPolicy.TVRating.allCases.map(\.rawValue),
            libraries: labeled(known).flatMap { snapshot in
                snapshot.libraries.map { FacetOptionInfo(id: $0.id, title: $0.title, detail: snapshot.serverName) }
            }.sorted { ($0.title, $0.detail ?? "") < ($1.title, $1.detail ?? "") },
            genres: uniqueOptions(known.flatMap { $0.items.flatMap(\.genres) }, key: ParentalPolicy.genreKey),
            collections: uniqueOptions(known.flatMap { $0.items.flatMap(\.collections) }, key: ParentalPolicy.collectionKey),
            titles: titles
        )
    }

    /// Saves the parental policy from Settings and rebuilds the lineup under it.
    func saveParental(_ draft: ParentalDraft) -> [ChannelInfo] {
        let known = accounts.compactMap { snapshots[$0.id] }
        let catalog = ParentalTitleCatalog(snapshots: labeled(known))
        var policy = parentalPolicy.resolvingTitles(in: catalog)
        apply(draft, to: &policy, catalog: catalog)
        parentalPolicy = policy
        parentalPreview = nil
        store?.save(policy, file: CoreStore.File.parental)
        rebuildLineup()
        return channelList()
    }

    /// `policy` with the draft's choices (titles are matched in `catalog`).
    func apply(_ draft: ParentalDraft, to policy: inout ParentalPolicy, catalog: ParentalTitleCatalog? = nil) {
        let catalog = catalog ?? ParentalTitleCatalog(snapshots: labeled(accounts.compactMap { snapshots[$0.id] }))
        let previous = policy
        policy.isEnabled = draft.isEnabled
        policy.usesCustomLineup = draft.usesCustomLineup
        policy.maximumMovieRating = ParentalPolicy.MovieRating(rawValue: draft.maximumMovieRating) ?? policy.maximumMovieRating
        policy.maximumTVRating = ParentalPolicy.TVRating(rawValue: draft.maximumTVRating) ?? policy.maximumTVRating
        policy.allowsUnrated = draft.allowsUnrated
        policy.allLibraries = draft.allLibraries
        policy.libraryIDs = Set(draft.libraryIDs)
        policy.allGenres = draft.allGenres
        policy.genreNames = Set(draft.genreNames)
        policy.selectedContentOnly = draft.selectedContentOnly
        policy.collectionNames = Set(draft.collectionNames)
        policy.allowedTitles = titles(draft.allowedTitleIDs, catalog: catalog, saved: previous.allowedTitles)
        policy.blockedTitles = titles(draft.blockedTitleIDs, catalog: catalog, saved: previous.blockedTitles)
        policy.channelCustomization.customChannels = parentalChannels(draft.customChannels, existing: previous.channelCustomization)
    }

    /// Custom-lineup channels from editor drafts, numbered after the lineup's own.
    private func parentalChannels(_ drafts: [ChannelDraft], existing: LineupCustomization) -> [ChannelDefinition] {
        var customization = LineupCustomization()
        for draft in drafts {
            var definition = existing.customChannels.first { $0.id == draft.id } ?? ChannelDefinition(
                id: draft.id ?? LineupCustomization.customChannelID(),
                number: customization.nextCustomChannelNumber,
                name: "",
                rule: ChannelRule(),
                ordering: .blockShuffle,
                source: .custom
            )
            definition.name = draft.name.trimmingCharacters(in: .whitespaces)
            definition.callSign = CallSign.make(from: definition.name)
            definition.rule = rule(from: draft, base: definition.rule)
            definition.ordering = ScheduleOrdering(rawValue: draft.ordering) ?? definition.ordering
            customization.customChannels.append(definition)
        }
        return customization.customChannels
    }

    private func titles(_ ids: [String], catalog: ParentalTitleCatalog, saved: [ParentalTitleIdentity]) -> [ParentalTitleIdentity] {
        let chosen = Set(ids)
        return catalog.identities(for: chosen) + saved.filter { chosen.contains(Self.savedID($0)) }
    }

    private static func savedID(_ identity: ParentalTitleIdentity) -> String {
        savedTitlePrefix + (identity.sourceIDs.sorted().first ?? identity.name)
    }

    /// Snapshots with server names that tell same-named servers apart.
    private func labeled(_ snapshots: [LibrarySnapshot]) -> [LibrarySnapshot] {
        let labels = Dictionary(accounts.map { account in
            let name = "\(account.name) · \(account.kind.displayName)"
            let duplicates = accounts.filter { $0.name == account.name && $0.kind == account.kind }
            return (account.id, duplicates.count > 1 ? "\(name) · \(account.baseURL.host() ?? "")" : name)
        }, uniquingKeysWith: { first, _ in first })
        return snapshots.map { snapshot in
            LibrarySnapshot(serverID: snapshot.serverID, serverName: labels[snapshot.serverID] ?? snapshot.serverName,
                libraries: snapshot.libraries, items: snapshot.items, refreshedAt: snapshot.refreshedAt)
        }
    }

    private func uniqueOptions(_ names: [String], key: (String) -> String) -> [FacetOptionInfo] {
        var seen: Set<String> = []
        return Set(names).sorted().compactMap { name in
            let id = key(name)
            guard !id.isEmpty, seen.insert(id).inserted else { return nil }
            return FacetOptionInfo(id: id, title: name, detail: nil)
        }
    }
}
