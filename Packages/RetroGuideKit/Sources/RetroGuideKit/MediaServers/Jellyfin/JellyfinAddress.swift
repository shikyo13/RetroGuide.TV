import Foundation

/// Turns what someone types for their server ("10.0.1.5", "jellyfin.home:8096",
/// "https://media.example.com/jellyfin") into the addresses worth trying, in order.
///
/// Forgiving about how addresses get typed or pasted: a page copied from the
/// browser ("…:8096/web/#/home.html"), a space or comma before the port, and
/// a scheme without a port all still find the server.
public enum JellyfinAddress {
    private static let schemeSeparator = "://"
    private static let secureScheme = "https"
    /// Where Jellyfin's own web app lives under the server's address.
    private static let webClientPaths = ["/web/index.html", "/web"]
    /// A port set off by spaces, a comma or a semicolon instead of a colon
    /// ("10.0.1.5 8096", "10.0.1.5, 8096", "10.0.1.5 :8096").
    private static let loosePortPattern = #"\s*[\s,;:]\s*(\d{1,5})(?=/|$)"#
    private static let portTemplate = ":$1"

    public static func candidates(from text: String) -> [URL] {
        let typed = tidied(text)
        guard !typed.isEmpty else { return [] }
        let full = typed.contains(schemeSeparator) ? typed : secureScheme + schemeSeparator + typed
        guard let parsed = URL(string: full).flatMap(normalized) else { return [] }
        // With a port, only there. Without one: the standard HTTPS proxy first,
        // then Jellyfin's native HTTPS port, then its usual port (which, over
        // plain HTTP, at least tells the viewer why).
        let places = parsed.port != nil
            ? [parsed]
            : [parsed, withPort(parsed, JellyfinAPI.defaultSecurePort), withPort(parsed, JellyfinAPI.defaultPort)].compactMap { $0 }
        // A path may be some page rather than where the server lives: the
        // same places without it come last.
        let roots = parsed.path.isEmpty ? [] : places.compactMap(withoutPath)
        return places + roots
    }

    /// `text` trimmed, with a loosely typed port joined to its host by a colon.
    static func tidied(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: loosePortPattern, with: portTemplate, options: .regularExpression)
    }

    /// Without a trailing slash, so API paths append cleanly, and without
    /// the web app's own page.
    private static func normalized(_ url: URL) -> URL? {
        guard SecureTransport.permits(url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.path = serverPath(components.path)
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// `path` as the server's base path: no trailing slashes and no web app page.
    private static func serverPath(_ path: String) -> String {
        var path = path
        while path.hasSuffix("/") { path.removeLast() }
        if let page = webClientPaths.first(where: { path.lowercased().hasSuffix($0) }) {
            path.removeLast(page.count)
        }
        while path.hasSuffix("/") { path.removeLast() }
        return path
    }

    /// `text` with an `http://` scheme replaced by `https://`; anything else unchanged.
    public static func upgradingInsecureScheme(_ text: String) -> String {
        let trimmed = tidied(text)
        let insecurePrefix = "http" + schemeSeparator
        guard trimmed.lowercased().hasPrefix(insecurePrefix) else { return trimmed }
        return secureScheme + schemeSeparator + trimmed.dropFirst(insecurePrefix.count)
    }

    /// The plain-HTTP address `text` means (Jellyfin's usual port unless one
    /// is given), when it's on the home network or a VPN; otherwise `nil`.
    public static func plainHTTP(from text: String) -> URL? {
        let trimmed = tidied(text)
        let withoutScheme = trimmed.range(of: schemeSeparator).map { String(trimmed[$0.upperBound...]) } ?? trimmed
        guard !withoutScheme.isEmpty,
              var components = URLComponents(string: "http" + schemeSeparator + withoutScheme),
              components.user == nil, components.password == nil else { return nil }
        if components.port == nil { components.port = JellyfinAPI.defaultPort }
        components.path = serverPath(components.path)
        components.query = nil
        components.fragment = nil
        guard let url = components.url, url.host()?.isEmpty == false, PlainHTTPOrigins.qualifies(url) else { return nil }
        return url
    }

    /// Like ``plainHTTP(from:)``, and also for a name that the network's DNS
    /// points at a home or VPN address (`jellyfin.example.com` set up to mean
    /// `192.168.1.20` at home): then that address, so plain HTTP never
    /// depends on the name keeping that meaning.
    public static func resolvedPlainHTTP(from text: String) async -> URL? {
        if let plain = plainHTTP(from: text) { return plain }
        let trimmed = tidied(text)
        let withoutScheme = trimmed.range(of: schemeSeparator).map { String(trimmed[$0.upperBound...]) } ?? trimmed
        guard var components = URLComponents(string: "http" + schemeSeparator + withoutScheme),
              let host = components.host, !host.isEmpty,
              let address = await HostResolver.firstIPv4(of: host),
              NetworkLocation.isPrivateOrVPN(ipv4: address) else { return nil }
        components.host = address
        return components.url.flatMap { plainHTTP(from: $0.absoluteString) }
    }

    private static func withPort(_ url: URL, _ port: Int) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.port = port
        return components?.url
    }

    /// `url` without its path, or `nil` when it has none: the fallback when
    /// the path was some page rather than where the server lives.
    public static func withoutPath(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false), !components.path.isEmpty else { return nil }
        components.path = ""
        return components.url
    }

}
