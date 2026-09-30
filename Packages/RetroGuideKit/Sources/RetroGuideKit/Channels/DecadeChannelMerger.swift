import Foundation

/// Keeps decade channels meaningful in libraries with few older (or newer)
/// titles: neighbouring decade channels that are each too thin to stand alone
/// merge into one channel covering their span ("80s–90s TV"); a merged
/// channel that is still too thin is dropped. A healthy decade channel never
/// absorbs a thin neighbour. TV and movie decade channels merge separately.
enum DecadeChannelMerger {
    typealias Resolved = (definition: ChannelDefinition, items: [MediaItem])

    /// `channels` are the decade channels in chronological order, empty ones included.
    static func merge(_ channels: [Resolved], minimumTitles: Int) -> [Resolved] {
        var result: [Resolved] = []
        let kinds = channels.map(\.definition.rule.kinds)
        for kind in uniqueInOrder(kinds) {
            var run: [Resolved] = []
            for channel in channels where channel.definition.rule.kinds == kind {
                if titleCount(channel.items) >= minimumTitles {
                    result += flushed(run, minimumTitles: minimumTitles)
                    run = []
                    result.append(channel)
                } else {
                    run.append(channel)
                }
            }
            result += flushed(run, minimumTitles: minimumTitles)
        }
        return result
    }

    /// A run of thin neighbours: one channel if together they're enough, else nothing.
    private static func flushed(_ untrimmed: [Resolved], minimumTitles: Int) -> [Resolved] {
        // Empty decades at either end add nothing and would stretch the name;
        // empty ones in between stay, so the span reads continuously.
        guard let firstFilled = untrimmed.firstIndex(where: { !$0.items.isEmpty }),
              let lastFilled = untrimmed.lastIndex(where: { !$0.items.isEmpty })
        else { return [] }
        let run = Array(untrimmed[firstFilled...lastFilled])
        let items = run.flatMap(\.items)
        guard let first = run.first, let last = run.last, titleCount(items) >= minimumTitles else { return [] }
        guard run.count > 1 else { return [first] }
        var definition = first.definition
        // Every member's id, so settings made on them carry over (see ``memberIDs(of:)``).
        definition.id = run.map(\.definition.id).joined(separator: Self.idSeparator)
        definition.name = name(for: run)
        definition.rule.decades = Set(run.flatMap(\.definition.rule.decades))
        // Merging never airs a title twice: channels in a run cover different decades.
        return [(definition, items)]
    }

    /// "Classic TV" when the run starts from the classic channel (it keeps
    /// that brand), otherwise the span, e.g. "80s–90s Movies".
    private static func name(for run: [Resolved]) -> String {
        guard let first = run.first, let last = run.last else { return "" }
        let isMovies = first.definition.rule.kinds == [.movie]
        let firstDecades = first.definition.rule.decades
        if firstDecades.count > 1 {
            return first.definition.name
        }
        let from = firstDecades.min().map(label(for:)) ?? ""
        let to = last.definition.rule.decades.max().map(label(for:)) ?? ""
        return "\(from)–\(to) \(isMovies ? Label.movies : Label.shows)"
    }

    private enum Label {
        static let shows = "TV"
        static let movies = "Movies"
        /// Decades before this are written short ("80s"), later ones in full ("2010s").
        static let fullYearsFrom = 2000
        static let centurySpan = 100
    }

    private static func label(for decade: Int) -> String {
        decade >= Label.fullYearsFrom ? "\(decade)s" : "\(decade % Label.centurySpan)s"
    }

    private static let idSeparator = "+"

    /// The ids of the decade channels a merged channel was made from (empty
    /// for any other channel).
    static func memberIDs(of definition: ChannelDefinition) -> Set<String> {
        guard definition.source == .decade, definition.id.contains(idSeparator) else { return [] }
        return Set(definition.id.components(separatedBy: idSeparator))
    }

    static func titleCount(_ items: [MediaItem]) -> Int {
        Set(items.map(\.showID)).count
    }

    private static func uniqueInOrder<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.filter { seen.insert($0).inserted }
    }
}
