import Foundation

/// Turns what someone types for their server ("10.0.1.5", "jellyfin.home:8096",
/// "https://media.example.com/jellyfin") into the addresses worth trying, in order.
public enum JellyfinAddress {
    private static let schemeSeparator = "://"
    private static let secureScheme = "https"

    public static func candidates(from text: String) -> [URL] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        // A full address is used as typed.
        if trimmed.contains(schemeSeparator) {
            return URL(string: trimmed).flatMap(normalized).map { [$0] } ?? []
        }
        guard let parsed = URL(string: JellyfinAPI.defaultScheme + schemeSeparator + trimmed),
              let host = parsed.host(), !host.isEmpty
        else { return [] }
        var urls: [URL] = []
        if parsed.port != nil {
            // A port was given: plain HTTP first (the default for a port), then HTTPS.
            urls.append(parsed)
            urls += secure(parsed).map { [$0] } ?? []
        } else {
            // Jellyfin's own port first; a name may also sit behind an HTTPS proxy.
            urls += withPort(parsed, JellyfinAPI.defaultPort).map { [$0] } ?? []
            urls += secure(parsed).map { [$0] } ?? []
            urls.append(parsed)
        }
        return urls.compactMap(normalized)
    }

    /// Without a trailing slash, so API paths append cleanly.
    private static func normalized(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false), components.host?.isEmpty == false else { return nil }
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

    private static func secure(_ url: URL) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = secureScheme
        return components?.url
    }
}
