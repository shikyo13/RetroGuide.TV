import Foundation

/// One title from `titles.tsv`: its ids and the Wikidata ids of its types and genres.
struct TitleRow {
    let imdb: UInt32?
    let tmdbMovie: UInt32?
    let tmdbShow: UInt32?
    let tvdb: UInt32?
    let types: [String]
    let genres: [String]

    private enum Column: Int, CaseIterable {
        case item, imdb, tmdbMovie, tmdbShow, tvdb, types, genres
    }

    private static let imdbTitlePrefix = "tt"

    static func parse(_ tsv: String) -> [TitleRow] {
        tsv.split(separator: "\n").dropFirst().compactMap { line in
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard columns.count == Column.allCases.count else { return nil }
            return TitleRow(
                imdb: columns[Column.imdb.rawValue].hasPrefix(imdbTitlePrefix) ? UInt32(columns[Column.imdb.rawValue].dropFirst(imdbTitlePrefix.count)) : nil,
                tmdbMovie: UInt32(columns[Column.tmdbMovie.rawValue]),
                tmdbShow: UInt32(columns[Column.tmdbShow.rawValue]),
                tvdb: UInt32(columns[Column.tvdb.rawValue]),
                types: columns[Column.types.rawValue].split(separator: " ").map(String.init),
                genres: columns[Column.genres.rawValue].split(separator: " ").map(String.init)
            )
        }
    }
}
