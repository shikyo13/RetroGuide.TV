import Foundation
import RetroGuideKit

/// Maps every title's Wikidata types and genres onto RetroGuide's genre
/// categories and writes the kit's classification table.
///
/// A type or genre maps through its English label with the same taxonomy that
/// reads server tags ("crime drama film" → crime, drama), unless
/// `wikidata-overrides.json` says otherwise (an empty list means "no category").
struct ClassificationBuilder {
    private struct Override: Decodable {
        let label: String
        let categories: [GenreCategory]
    }

    /// How many unmapped types and genres the report lists.
    private static let reportedUnmapped = 40

    let paths: Paths

    func build() throws {
        let rows = TitleRow.parse(try String(contentsOf: paths.titles, encoding: .utf8))
        let labels = try readLabels()
        let overrides = try JSONDecoder().decode([String: Override].self, from: Data(contentsOf: paths.overrides))
        var mapping: [String: Set<GenreCategory>] = [:]
        for (id, label) in labels {
            mapping[id] = overrides[id].map { Set($0.categories) } ?? GenreTaxonomy.shared.categories(for: [label])
        }

        var entries: [TitleClassification.Section: [UInt32: Set<GenreCategory>]] = [:]
        var unmapped: [String: Int] = [:]
        var classified = 0
        for row in rows {
            var categories = Set<GenreCategory>()
            for id in row.types + row.genres {
                if let mapped = mapping[id] {
                    categories.formUnion(mapped)
                } else {
                    unmapped[id, default: 0] += 1
                }
            }
            guard !categories.isEmpty else { continue }
            classified += 1
            let keys: [(TitleClassification.Section, UInt32?)] = [(.imdb, row.imdb), (.tmdbMovie, row.tmdbMovie), (.tmdbShow, row.tmdbShow), (.tvdb, row.tvdb)]
            for case let (section, id?) in keys {
                // The same id on two items (duplicates awaiting a merge): keep both.
                entries[section, default: [:]][id, default: []].formUnion(categories)
            }
        }

        let table = TitleClassification.encode(entries)
        try table.write(to: paths.output)
        print("\(classified) of \(rows.count) titles classified; table \(table.count / 1024) KB")
        for section in TitleClassification.Section.allCases {
            print("  \(section): \(entries[section]?.count ?? 0) ids")
        }
        print("Most used unmapped types and genres (add to wikidata-overrides.json if they matter):")
        for (id, uses) in unmapped.sorted(by: { $0.value > $1.value }).prefix(Self.reportedUnmapped) {
            print("  \(id) \(labels[id] ?? "(unlabeled)"): \(uses)")
        }
        print("Wrote \(paths.output.path)")
    }

    private func readLabels() throws -> [String: String] {
        var labels: [String: String] = [:]
        for line in try String(contentsOf: paths.labels, encoding: .utf8).split(separator: "\n").dropFirst() {
            let columns = line.split(separator: "\t", maxSplits: 1).map(String.init)
            if columns.count == 2 { labels[columns[0]] = columns[1] }
        }
        return labels
    }
}
