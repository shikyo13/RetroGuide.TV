import Foundation

/// Best-effort check of whether a server address is on the home network.
public enum NetworkLocation {
    private enum Pattern {
        static let localDomainSuffix = ".local"
        /// Plex's secure addresses embed the IP: `192-168-1-20.<hash>.plex.direct`.
        static let plexDirectSuffix = ".plex.direct"
        static let plexDirectSeparator: Character = "-"
        static let octetCount = 4
        static let privateSecondOctets172 = 16...31
    }

    public static func isLikelyLocal(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        if host == "localhost" || host.hasSuffix(Pattern.localDomainSuffix) {
            return true
        }
        if let ip = ipv4Octets(from: host) {
            return isPrivate(ip)
        }
        return false
    }

    private static func ipv4Octets(from host: String) -> [Int]? {
        var candidate = host
        if host.hasSuffix(Pattern.plexDirectSuffix), let first = host.split(separator: ".").first {
            candidate = first.replacingOccurrences(of: String(Pattern.plexDirectSeparator), with: ".")
        }
        let octets = candidate.split(separator: ".").compactMap { Int($0) }
        return octets.count == Pattern.octetCount && candidate.split(separator: ".").count == Pattern.octetCount ? octets : nil
    }

    private static func isPrivate(_ ip: [Int]) -> Bool {
        switch (ip[0], ip[1]) {
        case (10, _), (127, _), (192, 168): true
        case let (172, second): Pattern.privateSecondOctets172.contains(second)
        default: false
        }
    }
}
