import Foundation

/// Drops automatic channels that air nearly the same titles as one already
/// kept (a network channel that's really just the Anime channel, or an All
/// Shows channel in a library with no movies). Candidates are compared in
/// lineup order, so catch-all channels come first and Everything wins.
/// Channels keep their own content: nothing is moved between channels.
enum DuplicateChannelMerger {
    typealias Resolved = (definition: ChannelDefinition, items: [MediaItem])

    /// Keeps the channels (in lineup order) that no earlier kept channel
    /// shares `similarity` or more of their combined titles with.
    static func merge(_ channels: [Resolved], similarity: Double) -> [Resolved] {
        var kept: [(channel: Resolved, titles: Set<String>)] = []
        for channel in channels {
            let own = Set(channel.items.map(\.showID))
            let isDuplicate = kept.contains { other in
                Double(own.intersection(other.titles).count) / Double(max(own.union(other.titles).count, 1)) >= similarity
            }
            if !isDuplicate {
                kept.append((channel, own))
            }
        }
        return kept.map(\.channel)
    }
}
