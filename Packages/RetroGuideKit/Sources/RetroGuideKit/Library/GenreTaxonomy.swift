import Foundation

/// Maps raw genre strings ("Sci-Fi & Fantasy", "Komödie", "Crime Drama") to
/// ``GenreCategory`` values using `Resources/genre-taxonomy.json`.
public struct GenreTaxonomy: Sendable {
    private static let resourceName = "genre-taxonomy"
    /// Longest word sequence tried when splitting compound genres ("science fiction").
    private static let maximumPhraseWords = 3

    public static let shared = (try? GenreTaxonomy.bundled()) ?? GenreTaxonomy(lookup: [:])

    private let lookup: [String: Set<GenreCategory>]

    init(lookup: [String: Set<GenreCategory>]) {
        self.lookup = lookup
    }

    static func bundled() throws -> GenreTaxonomy {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json") else {
            throw ChannelCatalog.CatalogError.missingResource(resourceName)
        }
        let file = try JSONDecoder().decode(TaxonomyFile.self, from: Data(contentsOf: url))
        var lookup: [String: Set<GenreCategory>] = [:]
        for (name, synonyms) in file.categories {
            guard let category = GenreCategory(rawValue: name) else { continue }
            for synonym in synonyms {
                lookup[key(synonym), default: []].insert(category)
            }
        }
        return GenreTaxonomy(lookup: lookup)
    }

    /// Categories for a set of raw genres. Unknown compound genres are split into
    /// phrases ("crime drama" → crime + drama).
    public func categories(for genres: [String]) -> Set<GenreCategory> {
        var result = Set<GenreCategory>()
        for genre in genres {
            let normalized = Self.key(genre)
            if let direct = lookup[normalized] {
                result.formUnion(direct)
            } else {
                result.formUnion(phraseMatches(in: normalized))
            }
        }
        return result
    }

    private func phraseMatches(in normalized: String) -> Set<GenreCategory> {
        let words = normalized.split(separator: " ").map(String.init)
        var result = Set<GenreCategory>()
        for length in 1...Self.maximumPhraseWords where length <= words.count {
            for start in 0...(words.count - length) {
                if let match = lookup[words[start..<(start + length)].joined(separator: " ")] {
                    result.formUnion(match)
                }
            }
        }
        return result
    }

    /// Lowercased, diacritic-free, punctuation collapsed to single spaces.
    static func key(_ raw: String) -> String {
        TextNormalizer.key(raw)
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ")
            .joined(separator: " ")
    }

    private struct TaxonomyFile: Decodable {
        let categories: [String: [String]]
    }
}

/// Recognizes anime even when a library has no "Anime" genre tag.
enum AnimeDetector {
    private static let japanKeys: Set<String> = ["japan", "jp", "japon", "japao", "giappone"]
    private static let libraryKeyword = "anime"

    static func isAnime(categories: Set<GenreCategory>, countries: [String], libraryTitle: String?) -> Bool {
        if categories.contains(.anime) {
            return true
        }
        if categories.contains(.animation), countries.contains(where: { japanKeys.contains(GenreTaxonomy.key($0)) }) {
            return true
        }
        return libraryTitle.map { GenreTaxonomy.key($0).contains(libraryKeyword) } ?? false
    }
}
