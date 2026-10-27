import Foundation

/// Device-local restrictions applied to original server items before duplicate merging.
public struct ParentalPolicy: Codable, Equatable, Sendable {
    public var isEnabled = false
    public var usesCustomLineup = false
    public var channelCustomization = LineupCustomization()
    public var maximumMovieRating: MovieRating = .pg
    public var maximumTVRating: TVRating = .pg
    public var allowsUnrated = false
    public var allLibraries = true
    public var libraryIDs: Set<String> = []
    public var allGenres = true
    public var genreNames: Set<String> = []
    public var selectedContentOnly = false
    public var collectionNames: Set<String> = []
    public var titleIDs: Set<String> = []
    public var blockedTitleIDs: Set<String> = []
    public var allowedTitles: [ParentalTitleIdentity] = []
    public var blockedTitles: [ParentalTitleIdentity] = []

    public init() {}

    public func activeCustomization(regular: LineupCustomization) -> LineupCustomization {
        guard isEnabled && usesCustomLineup else { return regular }
        var result = channelCustomization
        result.disabledSources = Set(ChannelSource.allCases)
        return result
    }

    public var hasTitleSelections: Bool {
        !titleIDs.isEmpty || !blockedTitleIDs.isEmpty || !allowedTitles.isEmpty || !blockedTitles.isEmpty
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try values.decode(Bool.self, forKey: .isEnabled)
        usesCustomLineup = try values.decodeIfPresent(Bool.self, forKey: .usesCustomLineup) ?? false
        channelCustomization = try values.decodeIfPresent(LineupCustomization.self, forKey: .channelCustomization) ?? LineupCustomization()
        maximumMovieRating = try values.decode(MovieRating.self, forKey: .maximumMovieRating)
        maximumTVRating = try values.decode(TVRating.self, forKey: .maximumTVRating)
        allowsUnrated = try values.decode(Bool.self, forKey: .allowsUnrated)
        allLibraries = try values.decode(Bool.self, forKey: .allLibraries)
        libraryIDs = try values.decode(Set<String>.self, forKey: .libraryIDs)
        allGenres = try values.decodeIfPresent(Bool.self, forKey: .allGenres) ?? true
        genreNames = try values.decodeIfPresent(Set<String>.self, forKey: .genreNames) ?? []
        selectedContentOnly = try values.decode(Bool.self, forKey: .selectedContentOnly)
        collectionNames = try values.decode(Set<String>.self, forKey: .collectionNames)
        titleIDs = try values.decodeIfPresent(Set<String>.self, forKey: .titleIDs) ?? []
        blockedTitleIDs = try values.decodeIfPresent(Set<String>.self, forKey: .blockedTitleIDs) ?? []
        allowedTitles = try values.decodeIfPresent([ParentalTitleIdentity].self, forKey: .allowedTitles) ?? []
        blockedTitles = try values.decodeIfPresent([ParentalTitleIdentity].self, forKey: .blockedTitles) ?? []
    }

    public enum MovieRating: String, Codable, CaseIterable, Sendable {
        case g = "G", pg = "PG", pg13 = "PG-13", r = "R", nc17 = "NC-17"
    }

    public enum TVRating: String, Codable, CaseIterable, Sendable {
        case y = "TV-Y", y7 = "TV-Y7", g = "TV-G", pg = "TV-PG", tv14 = "TV-14", ma = "TV-MA"
    }

    public enum Exclusion: String, Sendable {
        case library = "Library is not allowed"
        case title = "Title is blocked"
        case genre = "Genre is not allowed"
        case selection = "Content has not been selected"
        case unrated = "Rating is missing or unrecognized"
        case rating = "Rating exceeds the limit"
    }

    /// Original source id, retained to migrate selections saved before cross-server matching.
    public static func titleID(for item: MediaItem) -> String { item.seriesID ?? item.id }

    public static func collectionKey(_ name: String) -> String { TextNormalizer.key(name) }

    public static func genreKey(_ name: String) -> String { TextNormalizer.key(name) }

    public func exclusion(for item: MediaItem) -> Exclusion? {
        guard isEnabled else { return nil }
        guard allLibraries || libraryIDs.contains(item.libraryID) else { return .library }
        let titleID = Self.titleID(for: item)
        let identity = ParentalTitleIdentity(item: item)
        guard !blockedTitleIDs.contains(titleID), !blockedTitles.contains(where: { $0.matches(identity, blocking: true) }) else { return .title }
        if selectedContentOnly && !titleIDs.contains(titleID) && !allowedTitles.contains(where: { $0.matches(identity) })
            && TextNormalizer.keys(item.collections).isDisjoint(with: TextNormalizer.keys(collectionNames)) { return .selection }
        guard allGenres || !TextNormalizer.keys(item.genres).isDisjoint(with: TextNormalizer.keys(genreNames)) else { return .genre }
        return ratingExclusion(for: item)
    }

    private func ratingExclusion(for item: MediaItem) -> Exclusion? {
        guard let rating = Self.normalizedRating(item.contentRating) else { return allowsUnrated ? nil : .unrated }
        switch item.kind {
        case .movie:
            guard let value = MovieRating(rawValue: rating),
                  let rank = MovieRating.allCases.firstIndex(of: value),
                  let maximum = MovieRating.allCases.firstIndex(of: maximumMovieRating) else {
                return allowsUnrated ? nil : .unrated
            }
            return rank <= maximum ? nil : .rating
        case .episode:
            guard let value = TVRating(rawValue: rating == "TV-Y7-FV" ? "TV-Y7" : rating),
                  let rank = TVRating.allCases.firstIndex(of: value),
                  let maximum = TVRating.allCases.firstIndex(of: maximumTVRating) else {
                return allowsUnrated ? nil : .unrated
            }
            return rank <= maximum ? nil : .rating
        }
    }

    public func allows(_ item: MediaItem) -> Bool { exclusion(for: item) == nil }

    public func filtering(_ snapshots: [LibrarySnapshot]) -> [LibrarySnapshot] {
        guard isEnabled else { return snapshots }
        let genres = TextNormalizer.keys(genreNames)
        let collections = TextNormalizer.keys(collectionNames)
        let collectionMembers: Set<String> = collections.isEmpty ? [] : Set(snapshots.flatMap { snapshot in
            snapshot.items.filter {
                (allLibraries || libraryIDs.contains($0.libraryID))
                    && !TextNormalizer.keys($0.collections).isDisjoint(with: collections)
            }.map(Self.titleID)
        })
        let catalog = hasTitleSelections || !collectionMembers.isEmpty ? ParentalTitleCatalog(snapshots: snapshots) : nil
        let allowed = catalog?.sourceIDs(for: allowedTitles, legacyIDs: titleIDs.union(collectionMembers)) ?? []
        let blocked = catalog?.sourceIDs(for: blockedTitles, legacyIDs: blockedTitleIDs, blocking: true) ?? []
        return snapshots.map { snapshot in
            LibrarySnapshot(serverID: snapshot.serverID, serverName: snapshot.serverName,
                libraries: snapshot.libraries.filter { allLibraries || libraryIDs.contains($0.id) },
                items: snapshot.items.filter { item in
                    let title = Self.titleID(for: item)
                    return (allLibraries || libraryIDs.contains(item.libraryID))
                        && !blocked.contains(title)
                        && (!selectedContentOnly || allowed.contains(title))
                        && (allGenres || !TextNormalizer.keys(item.genres).isDisjoint(with: genres))
                        && ratingExclusion(for: item) == nil
                }, refreshedAt: snapshot.refreshedAt)
        }
    }

    public func resolvingTitles(in catalog: ParentalTitleCatalog) -> Self {
        var result = self
        result.allowedTitles = catalog.expanding(allowedTitles, legacyIDs: titleIDs)
        result.blockedTitles = catalog.expanding(blockedTitles, legacyIDs: blockedTitleIDs, blocking: true)
        let known = Set(catalog.titles.flatMap { $0.identity.sourceIDs })
        result.titleIDs.subtract(known)
        result.blockedTitleIDs.subtract(known)
        return result
    }

    private static func normalizedRating(_ value: String?) -> String? {
        guard let value else { return nil }
        var rating = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        for prefix in ["US/", "US:", "MPAA/"] where rating.hasPrefix(prefix) {
            rating = String(rating.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return rating.isEmpty ? nil : rating
    }
}
