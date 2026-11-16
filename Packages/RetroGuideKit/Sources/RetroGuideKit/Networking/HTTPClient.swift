import Foundation

public enum HTTPError: Error, Equatable, LocalizedError {
    case secureConnectionRequired
    case invalidURL
    case invalidResponse
    case unauthorized
    case status(Int)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .secureConnectionRequired: String(localized: "A secure HTTPS connection is required. Configure HTTPS with a trusted certificate on your server, then update its address.", bundle: .module)
        case .invalidURL: String(localized: "The server address is not valid.", bundle: .module)
        case .invalidResponse: String(localized: "The server sent an unexpected response.", bundle: .module)
        case .unauthorized: String(localized: "The server rejected the sign-in. Please sign in again.", bundle: .module)
        case .status(429): String(localized: "Too many requests. Please wait a moment before trying again.", bundle: .module)
        case let .status(code): String(localized: "The server responded with error \(code).", bundle: .module, comment: "%lld is an HTTP status code, such as 404.")
        case let .decoding(detail): String(localized: "The server's response could not be read (\(detail)).", bundle: .module, comment: "%@ is a technical decoding error, shown untranslated.")
        }
    }
}

/// Thin async wrapper around `URLSession` with status validation and JSON decoding.
public struct HTTPClient: Sendable {
    private enum StatusCode {
        static let success = 200..<300
        static let unauthorized: Set<Int> = [401, 403]
    }

    private let session: URLSession
    private let decoder: JSONDecoder

    public init(session: URLSession = .shared, decoder: JSONDecoder = JSONDecoder()) {
        self.session = session
        self.decoder = decoder
    }

    /// For requests a viewer is waiting on (starting a stream, its tracks,
    /// ending it): a session of their own, so they never queue behind a
    /// library download's many requests to the same server.
    public static let playback = HTTPClient(session: URLSession(configuration: .playbackRequests))

    /// The same session, decoding JSON with `decoder`.
    public func decoding(with decoder: JSONDecoder) -> HTTPClient {
        HTTPClient(session: session, decoder: decoder)
    }

    public func data(for request: URLRequest, rateLimitRetries: Int = 0) async throws -> Data {
        try SecureTransport.requireHTTPS(request.url)
        var retries = 0
        while true {
            try Task.checkCancellation()
            let (data, response) = try await session.data(for: request, delegate: SecureRedirectDelegate.shared)
            guard let http = response as? HTTPURLResponse else {
                throw HTTPError.invalidResponse
            }
            if http.statusCode == 429, retries < rateLimitRetries,
               let delay = RateLimitRetry.delay(header: http.value(forHTTPHeaderField: "Retry-After"), attempt: retries) {
                retries += 1
                try await Task.sleep(for: .seconds(delay))
                continue
            }
            if StatusCode.unauthorized.contains(http.statusCode) {
                throw HTTPError.unauthorized
            }
            guard StatusCode.success.contains(http.statusCode) else {
                throw HTTPError.status(http.statusCode)
            }
            return data
        }
    }

    public func decode<T: Decodable>(_ type: T.Type, for request: URLRequest, rateLimitRetries: Int = 0) async throws -> T {
        let data = try await data(for: request, rateLimitRetries: rateLimitRetries)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HTTPError.decoding(String(describing: error))
        }
    }
}

/// Convenience for building requests from a base URL, path and query.
public struct RequestBuilder: Sendable {
    public let baseURL: URL
    public let headers: [String: String]
    public let timeout: TimeInterval

    public init(baseURL: URL, headers: [String: String], timeout: TimeInterval) {
        self.baseURL = baseURL
        self.headers = headers
        self.timeout = timeout
    }

    public func url(path: String, query: [URLQueryItem] = []) throws -> URL {
        try SecureTransport.requireHTTPS(baseURL)
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw HTTPError.invalidURL
        }
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = basePath + path
        if !query.isEmpty {
            components.queryItems = (components.queryItems ?? []) + query
        }
        // `+` is legal in queries but many servers decode it as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else {
            throw HTTPError.invalidURL
        }
        return url
    }

    public func request(
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        extraHeaders: [String: String] = [:]
    ) throws -> URLRequest {
        var request = URLRequest(url: try url(path: path, query: query), timeoutInterval: timeout)
        request.httpMethod = method
        headers.merging(extraHeaders) { _, new in new }.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return request
    }
}

private extension URLSessionConfiguration {
    /// Uncached, with a few connections per server kept for playback.
    static var playbackRequests: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = PlaybackSession.connectionsPerServer
        return configuration
    }
}

private enum PlaybackSession {
    static let connectionsPerServer = 4
}
