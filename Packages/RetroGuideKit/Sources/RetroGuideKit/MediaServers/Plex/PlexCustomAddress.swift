import Foundation

/// Turns what someone types as a server address ("100.101.102.103",
/// "100.101.102.103:32400", a hostname or a full URL) into a URL to connect to.
///
/// A bare IP becomes Plex's secure `a-b-c-d.<hash>.plex.direct` address for that
/// IP when the server's hash is known, so it works with the server's certificate.
public enum PlexCustomAddress {
    private enum Defaults {
        static let port = 32_400
        static let secureScheme = "https"
        static let plainScheme = "http"
        static let plexDirectSuffix = "plex.direct"
        static let octetCount = 4
        static let schemeSeparator = "://"
    }

    public static func url(from input: String, serverURL: URL?) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains(Defaults.schemeSeparator) {
            return URL(string: trimmed)
        }
        let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
        let host = parts[0]
        let port = parts.count > 1 ? Int(parts[1]) : Defaults.port
        guard let port else { return nil }
        if isIPv4(host) {
            if let hash = plexDirectHash(of: serverURL) {
                let dashed = host.replacingOccurrences(of: ".", with: "-")
                return URL(string: "\(Defaults.secureScheme)://\(dashed).\(hash).\(Defaults.plexDirectSuffix):\(port)")
            }
            return URL(string: "\(Defaults.plainScheme)://\(host):\(port)")
        }
        return URL(string: "\(Defaults.secureScheme)://\(host):\(port)")
    }

    /// The server-specific part of a `…​.<hash>.plex.direct` host.
    static func plexDirectHash(of url: URL?) -> String? {
        guard let labels = url?.host()?.split(separator: "."), labels.count == 4,
              labels.suffix(2).joined(separator: ".") == Defaults.plexDirectSuffix
        else { return nil }
        return String(labels[1])
    }

    private static func isIPv4(_ host: String) -> Bool {
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        return octets.count == Defaults.octetCount && octets.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
    }
}
