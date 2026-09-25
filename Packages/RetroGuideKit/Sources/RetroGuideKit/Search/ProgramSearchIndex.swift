import Foundation

/// A searchable title (a show or a movie) and the channels that air it.
public struct SearchableTitle: Sendable, Identifiable, Hashable {
    /// Normalized title, also the identity.
    public let id: String
    public let title: String
    public let kind: MediaKind
    /// A representative item, for artwork.
    public let sample: MediaItem
    public let channelIDs: [String]
}

/// One search result: a title plus its soonest airing (if any within the horizon).
public struct SearchResult: Sendable, Identifiable, Hashable {
    public let title: SearchableTitle
    public let channel: Channel?
    public let airing: ScheduledProgram?

    public var id: String { title.id }

    public func isAiring(at date: Date) -> Bool {
        airing?.contains(date) ?? false
    }
}

/// Title search over the current lineup, built once per lineup so typing stays fast.
public struct ProgramSearchIndex: Sendable {
    public enum Defaults {
        public static let resultLimit = 30
        /// How far ahead to look for the next airing of a result.
        public static let horizon: TimeInterval = 48 * ScheduleConstants.secondsPerHour
    }

    private let titles: [SearchableTitle]
    private let channelsByID: [String: Channel]

    public static let empty = ProgramSearchIndex(channels: [])

    public init(channels: [Channel]) {
        var entries: [String: (title: String, kind: MediaKind, sample: MediaItem, channelIDs: [String])] = [:]
        for channel in channels where !channel.isHidden {
            var seenOnChannel = Set<String>()
            for item in channel.items {
                let key = TextNormalizer.key(item.headline)
                guard seenOnChannel.insert(key).inserted else { continue }
                if entries[key] == nil {
                    entries[key] = (item.headline, item.kind, item, [])
                }
                entries[key]?.channelIDs.append(channel.id)
            }
        }
        titles = entries
            .map { SearchableTitle(id: $0.key, title: $0.value.title, kind: $0.value.kind, sample: $0.value.sample, channelIDs: $0.value.channelIDs) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        channelsByID = Dictionary(channels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Titles matching `query`, best matches first (prefix before substring),
    /// each with its soonest airing across all channels that carry it.
    public func search(
        _ query: String,
        at now: Date,
        limit: Int = Defaults.resultLimit,
        horizon: TimeInterval = Defaults.horizon
    ) -> [SearchResult] {
        let needle = TextNormalizer.key(query)
        guard !needle.isEmpty else { return [] }
        let prefixMatches = titles.filter { $0.id.hasPrefix(needle) }
        let otherMatches = titles.filter { !$0.id.hasPrefix(needle) && $0.id.contains(needle) }
        return (prefixMatches + otherMatches)
            .prefix(limit)
            .map { result(for: $0, at: now, horizon: horizon) }
    }

    private func result(for title: SearchableTitle, at now: Date, horizon: TimeInterval) -> SearchResult {
        let window = DateInterval(start: now, duration: horizon)
        var best: (channel: Channel, program: ScheduledProgram)?
        for channelID in title.channelIDs {
            guard let channel = channelsByID[channelID],
                  let program = channel.timeline.programs(overlapping: window)
                      .first(where: { TextNormalizer.key($0.item.headline) == title.id })
            else { continue }
            if let current = best, current.program.start <= program.start {
                continue
            }
            best = (channel, program)
        }
        return SearchResult(
            title: title,
            channel: best?.channel ?? title.channelIDs.first.flatMap { channelsByID[$0] },
            airing: best?.program
        )
    }
}
