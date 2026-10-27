import Foundation

/// Answers JSON requests from the Android app:
/// `{"method": "guide", "params": {...}}` → `{"ok": true, "result": ...}` or
/// `{"ok": false, "error": "message"}`.
///
/// Requests run one at a time against ``CoreState``; a caller blocks until
/// its answer is ready, so Kotlin calls from a background dispatcher.
public final class Core: Sendable {
    public init() {}

    public static let shared = Core()

    let state = CoreState()

    /// Answers `request` (blocking).
    public func handle(_ request: String) -> String {
        let answer = Answer()
        let done = DispatchSemaphore(value: 0)
        Task.detached { [self] in
            answer.text = await respond(to: request)
            done.signal()
        }
        done.wait()
        return answer.text
    }

    /// Answers `request`.
    public func respond(to request: String) async -> String {
        let data = Data(request.utf8)
        do {
            let method = try CoreCoding.decoder.decode(MethodName.self, from: data).method
            guard let route = Routes.table[method] else { throw CoreError.unknownMethod(method) }
            let result = try await route(state, data)
            return try Self.text(Success(result: result))
        } catch {
            return (try? Self.text(Failure(error: CoreError.message(for: error)))) ?? Self.encodingFailure
        }
    }

    private static func text(_ value: some Encodable) throws -> String {
        String(decoding: try CoreCoding.encoder.encode(value), as: UTF8.self)
    }

    private static let encodingFailure = #"{"ok":false,"error":"The response could not be encoded."}"#
}

/// The text handed back from the task that produced it.
private final class Answer: @unchecked Sendable {
    var text = ""
}

private struct MethodName: Decodable {
    let method: String
}

private struct Success: Encodable {
    let ok = true
    let result: AnyEncodable
}

private struct Failure: Encodable {
    let ok = false
    let error: String
}

/// Dates cross the bridge as seconds since 1970.
enum CoreCoding {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()
}

/// A handler's result, whatever its type.
struct AnyEncodable: Encodable, Sendable {
    private let encodeValue: @Sendable (Encoder) throws -> Void

    init(_ value: some Encodable & Sendable) {
        encodeValue = { try value.encode(to: $0) }
    }

    func encode(to encoder: Encoder) throws {
        try encodeValue(encoder)
    }
}

enum CoreError: LocalizedError {
    case unknownMethod(String)
    case notStarted
    case unknownServer
    case unknownChannel
    case notLinked
    case nothingScheduled

    var errorDescription: String? {
        switch self {
        case let .unknownMethod(method): "Unknown request: \(method)"
        case .notStarted: "The core hasn't been started."
        case .unknownServer: "That server isn't connected."
        case .unknownChannel: "That channel isn't in the lineup."
        case .notLinked: "Link a Plex account first."
        case .nothingScheduled: "Nothing is scheduled on this channel."
        }
    }

    static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}
