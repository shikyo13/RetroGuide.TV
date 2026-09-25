import Foundation

/// Normalizes free-form metadata ("Sci-Fi & Fantasy", "Café") into comparison keys.
enum TextNormalizer {
    static func key(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func keys<S: Sequence>(_ values: S) -> Set<String> where S.Element == String {
        Set(values.map(key))
    }
}
