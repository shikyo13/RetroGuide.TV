import Foundation

/// Turns what someone types for their server ("10.0.1.5", "jellyfin.home:8096",
/// "https://media.example.com/jellyfin") into the addresses worth trying, in order.
public enum JellyfinAddress {
    private static let schemeSeparator = "://"
    private static let secureScheme = "https"
    private static let securePort = 8_920

    public static func candidates(from text: String) -> [URL] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        // A full address is used as typed.
        if trimmed.contains(schemeSeparator) {
            return URL(string: trimmed).flatMap(normalized).map { [$0] } ?? []
        }
        guard let parsed = URL(string: secureScheme + schemeSeparator + trimmed) else { return [] }
        if parsed.port != nil { return normalized(parsed).map { [$0] } ?? [] }
        // Standard HTTPS proxy first, then Jellyfin's native HTTPS port.
        return [parsed, withPort(parsed, securePort)].compactMap { $0.flatMap(normalized) }
    }

    /// Without a trailing slash, so API paths append cleanly.
    private static func normalized(_ url: URL) -> URL? {
        guard SecureTransport.permits(url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        while components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func withPort(_ url: URL, _ port: Int) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.port = port
        return components?.url
    }

}
