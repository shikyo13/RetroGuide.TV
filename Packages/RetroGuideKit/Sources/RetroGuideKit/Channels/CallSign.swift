import Foundation

/// Generates short station identifiers ("Adult Swim" → "AS", "HBO" → "HBO").
public enum CallSign {
    public static let maximumLength = 4

    public static func make(from name: String) -> String {
        let words = name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let compact = words.joined()
        if compact.count <= maximumLength {
            return compact.uppercased()
        }
        if words.count > 1 {
            let initials = String(words.compactMap(\.first)).prefix(maximumLength)
            return initials.uppercased()
        }
        return String(compact.prefix(maximumLength)).uppercased()
    }

    /// Returns `callSign`, or a numbered variant ("ANIM" → "ANI2") if it is already taken.
    public static func unique(_ callSign: String, avoiding used: inout Set<String>) -> String {
        if used.insert(callSign).inserted {
            return callSign
        }
        let stem = String(callSign.prefix(maximumLength - 1))
        var suffix = 2
        while !used.insert("\(stem)\(suffix)").inserted {
            suffix += 1
        }
        return "\(stem)\(suffix)"
    }
}
