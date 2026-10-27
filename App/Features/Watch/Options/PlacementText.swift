import RetroGuideKit

/// "Why is this here?" in words: what the channel takes, and which of that
/// the show or movie has.
enum PlacementText {
    static func explanation(of placement: TitlePlacement?, title: String, on channel: Channel) -> String {
        let rule = channel.definition.rule
        switch channel.definition.source {
        case .series:
            return "\(channel.name) airs \(title) around the clock."
        case .custom:
            return "\(title) matches the rules you set for \(channel.name)."
        case .library:
            return "\(channel.name) carries everything in one of your libraries, including \(title)."
        default:
            break
        }
        if rule.isCatchAll {
            return "\(channel.name) carries every \(rule.kinds == [.movie] ? "movie" : rule.kinds == [.episode] ? "show" : "show and movie") in your library."
        }
        guard let placement else {
            return "\(title) matches what \(channel.name) is about."
        }
        if let network = placement.matchedNetworks.first {
            return "\(title) aired on \(network)."
        }
        if let collection = placement.matchedCollections.first {
            return "\(title) is in your \(collection) collection."
        }
        var sentences: [String] = []
        if let decade = placement.matchedDecade {
            sentences.append("\(title) is from the \(Decade.label(for: decade)).")
        }
        if !placement.matchedCategories.isEmpty {
            let genres = list(placement.matchedCategories.map(\.displayName).sorted())
            sentences.append("\(channel.name) is for \(list(rule.categories.map(\.displayName).sorted())), and \(title) is \(genres), going by \(source(placement.source)).")
        } else if !rule.keywords.isEmpty {
            sentences.append("\(title)'s title matches \(channel.name)'s theme.")
        }
        return sentences.isEmpty ? "\(title) matches what \(channel.name) is about." : sentences.joined(separator: " ")
    }

    private static func source(_ source: CategorySource) -> String {
        switch source {
        case .classification: "RetroGuide's title data, checked against your server's genre tags"
        case .server: "your server's genre tags"
        }
    }

    /// "A", "A or B", "A, B or C".
    private static func list(_ items: [String]) -> String {
        guard items.count > 1, let last = items.last else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " or " + last
    }
}
