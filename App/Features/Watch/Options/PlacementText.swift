import Foundation
import RetroGuideKit

/// "Why is this here?" in words: what the channel takes, and which of that
/// the show or movie has.
enum PlacementText {
    static func explanation(of placement: TitlePlacement?, title: String, on channel: Channel) -> String {
        let rule = channel.definition.rule
        switch channel.definition.source {
        case .series:
            return String(localized: "\(channel.name) airs \(title) around the clock.")
        case .custom:
            return String(localized: "\(title) matches the rules you set for \(channel.name).")
        case .library:
            return String(localized: "\(channel.name) carries everything in one of your libraries, including \(title).")
        default:
            break
        }
        if rule.isCatchAll {
            return catchAll(rule.kinds, on: channel)
        }
        guard let placement else {
            return String(localized: "\(title) matches what \(channel.name) is about.")
        }
        if let network = placement.matchedNetworks.first {
            return String(localized: "\(title) aired on \(network).", comment: "A show and the TV network it aired on")
        }
        if let collection = placement.matchedCollections.first {
            return String(localized: "\(title) is in your \(collection) collection.")
        }
        var sentences: [String] = []
        if let decade = placement.matchedDecade {
            sentences.append(String(localized: "\(title) is from the \(Decade.label(for: decade)).", comment: "A show or movie and its decade: “Cheers is from the 1980s.”"))
        }
        if !placement.matchedCategories.isEmpty {
            let genres = list(placement.matchedCategories.map(\.displayName).sorted())
            let channelGenres = list(rule.categories.map(\.displayName).sorted())
            sentences.append(categoryMatch(channel: channel.name, channelGenres: channelGenres, title: title, genres: genres, source: placement.source))
        } else if !rule.keywords.isEmpty {
            sentences.append(String(localized: "\(title)'s title matches \(channel.name)'s theme."))
        }
        return sentences.isEmpty ? String(localized: "\(title) matches what \(channel.name) is about.") : sentences.joined(separator: " ")
    }

    private static func catchAll(_ kinds: Set<MediaKind>, on channel: Channel) -> String {
        if kinds == [.movie] {
            return String(localized: "\(channel.name) carries every movie in your library.")
        }
        if kinds == [.episode] {
            return String(localized: "\(channel.name) carries every show in your library.")
        }
        return String(localized: "\(channel.name) carries every show and movie in your library.")
    }

    /// Which genres the channel takes, which of them the title has, and where that came from.
    private static func categoryMatch(channel: String, channelGenres: String, title: String, genres: String, source: CategorySource) -> String {
        switch source {
        case .classification:
            String(localized: "\(channel) is for \(channelGenres), and \(title) is \(genres), going by RetroGuide's title data, checked against your server's genre tags.", comment: "Channel name, the genres it carries, a show or movie title, and the genres it has")
        case .server:
            String(localized: "\(channel) is for \(channelGenres), and \(title) is \(genres), going by your server's genre tags.", comment: "Channel name, the genres it carries, a show or movie title, and the genres it has")
        }
    }

    /// "A", "A or B", "A, B or C".
    private static func list(_ items: [String]) -> String {
        guard items.count > 1, let last = items.last else { return items.first ?? "" }
        let leading = items.dropLast().joined(separator: String(localized: ", ", comment: "Separator between items of a list of genres"))
        return String(localized: "\(leading) or \(last)", comment: "The end of a list of genres: “Comedy, Drama or Western”")
    }
}
