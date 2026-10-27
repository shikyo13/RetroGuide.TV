import Foundation

/// Server requests must use authenticated TLS, including redirect destinations.
public enum SecureTransport {
    private static let defaultPort = 443
    public static func permits(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false
            && url.user == nil && url.password == nil
    }

    public static func requireHTTPS(_ url: URL?) throws {
        guard let url, permits(url) else { throw HTTPError.secureConnectionRequired }
    }

    public static func permitsRedirect(from source: URL, to destination: URL) -> Bool {
        // Server-specific tokens must not be forwarded to another origin.
        permits(source) && permits(destination)
            && source.host?.lowercased() == destination.host?.lowercased()
            && (source.port ?? defaultPort) == (destination.port ?? defaultPort)
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
