import Foundation

public enum HTTPError: Error, Equatable, LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case status(Int)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: "The server address is not valid."
        case .invalidResponse: "The server sent an unexpected response."
        case .unauthorized: "The server rejected the sign-in. Please sign in again."
        case let .status(code): "The server responded with error \(code)."
        case let .decoding(detail): "The server's response could not be read (\(detail))."
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

    public func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HTTPError.invalidResponse
        }
        if StatusCode.unauthorized.contains(http.statusCode) {
            throw HTTPError.unauthorized
        }
        guard StatusCode.success.contains(http.statusCode) else {
            throw HTTPError.status(http.statusCode)
        }
        return data
    }

    public func decode<T: Decodable>(_ type: T.Type, for request: URLRequest) async throws -> T {
        let data = try await data(for: request)
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
