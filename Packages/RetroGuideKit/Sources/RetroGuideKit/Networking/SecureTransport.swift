import Foundation
import os

/// Server requests must use authenticated TLS, including redirect destinations.
public enum SecureTransport {
    private static let defaultPort = 443
    private static let defaultPlainPort = 80

    /// HTTPS, or plain HTTP to a home-network or VPN server the viewer chose
    /// to use without encryption (``PlainHTTPOrigins``). Never credentials in the URL.
    public static func permits(_ url: URL) -> Bool {
        guard url.host?.isEmpty == false, url.user == nil, url.password == nil else { return false }
        switch url.scheme?.lowercased() {
        case "https": return true
        case "http": return PlainHTTPOrigins.contains(url)
        default: return false
        }
    }

    public static func requireHTTPS(_ url: URL?) throws {
        guard let url, permits(url) else { throw HTTPError.secureConnectionRequired }
    }

    public static func permitsRedirect(from source: URL, to destination: URL) -> Bool {
        // Server-specific tokens must not be forwarded to another origin.
        permits(source) && permits(destination)
            && source.host?.lowercased() == destination.host?.lowercased()
            && port(of: source) == port(of: destination)
    }

    static func port(of url: URL) -> Int {
        url.port ?? (url.scheme?.lowercased() == "http" ? defaultPlainPort : defaultPort)
    }
}

/// Servers the viewer chose to use without encryption. Only addresses on the
/// home network or a VPN such as Tailscale qualify: plain HTTP is never used
/// across the internet.
public enum PlainHTTPOrigins {
    private struct Origins {
        /// Saved servers the viewer agreed for.
        var saved: Set<String> = []
        /// A server being set up, after the viewer agreed.
        var pending: Set<String> = []
    }

    private static let origins = OSAllocatedUnfairLock(initialState: Origins())

    /// Whether plain HTTP may ever be allowed for `url`'s address.
    public static func qualifies(_ url: URL) -> Bool {
        NetworkLocation.isLikelyLocal(url) || NetworkLocation.isLikelyVPN(url)
    }

    /// Allows plain HTTP to `url`'s host and port while a server is set up or
    /// its address changed, if it qualifies. Saving the server keeps it.
    public static func allowPending(_ url: URL) {
        guard qualifies(url), let key = key(url) else { return }
        origins.withLock { _ = $0.pending.insert(key) }
    }

    public static func clearPending() {
        origins.withLock { $0.pending = [] }
    }

    /// Replaces the saved servers' allowances.
    public static func set(_ urls: [URL]) {
        let keys = Set(urls.filter(qualifies).compactMap(key))
        origins.withLock { $0.saved = keys }
    }

    static func contains(_ url: URL) -> Bool {
        guard qualifies(url), let key = key(url) else { return false }
        return origins.withLock { $0.saved.contains(key) || $0.pending.contains(key) }
    }

    private static func key(_ url: URL) -> String? {
        guard let host = url.host()?.lowercased(), !host.isEmpty else { return nil }
        return "\(host):\(SecureTransport.port(of: url))"
    }
}

public final class SecureRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    public static let shared = SecureRedirectDelegate()

    public func urlSession(_ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let source = response.url, let destination = request.url,
              SecureTransport.permitsRedirect(from: source, to: destination) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
