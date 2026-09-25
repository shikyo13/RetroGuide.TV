import Foundation

/// Compares language codes written different ways ("en", "eng", "en-US").
enum LanguageCode {
    /// Codes meaning "no language" or "undetermined".
    private static let unknown: Set<String> = ["und", "mul", "zxx", "mis"]

    /// The two-letter code when one exists, otherwise the code as given; `nil`
    /// for empty or undetermined codes.
    static func normalized(_ code: String?) -> String? {
        guard let code, let primary = code.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first else {
            return nil
        }
        let identifier = String(primary)
        guard !unknown.contains(identifier) else { return nil }
        return Locale.LanguageCode(identifier).identifier(.alpha2) ?? identifier
    }
}
