import Foundation
import Network
import RetroGuideKit

/// Exposes only the active stream on loopback. All upstream traffic uses verified HTTPS.
@MainActor
final class LoopbackPlaybackRelay {
    enum Limits {
        static let connections = 12
        /// Media segments kept addressable: servers cut one-second segments, so a
        /// nine-hour playlist still fits without forgetting its start. Past this the
        /// oldest segment goes first, as a live window moves on.
        static let resources = 32_768
        /// Playlists, keys and initialization segments, which players keep reusing and
        /// which are therefore never forgotten while the stream plays.
        static let pinnedResources = 4_096
        static let headerBytes = 16_384
        static let sniffBytes = 16
        static let manifestBytes = 1_048_576
        static let bufferedBytes = 1_048_576
        static let timeout: TimeInterval = 30
        static let host = "127.0.0.1"
    }
    private var listener: NWListener?
    private var exchanges: [UUID: LoopbackPlaybackRelayExchange] = [:]
    private var resources: [String: URL] = [:]
    private var identifiers: [URL: String] = [:]
    /// Segments that may be forgotten, oldest first.
    private var segmentOrder: [String] = []
    private var pinned: Set<String> = []
    private var nextResource = 0
    private let secret = UUID().uuidString + UUID().uuidString
    private let origin: URL
    private var port: NWEndpoint.Port?
    private var ready: CheckedContinuation<URL, any Error>?
    private var stopped = false

    init(origin: URL) throws {
        try SecureTransport.requireHTTPS(origin)
        self.origin = origin
    }

    func start() async throws -> URL {
        try Task.checkCancellation()
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection) ?? connection.cancel() }
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                ready = continuation
                listener.stateUpdateHandler = { [weak self] state in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        switch state {
                        case .ready:
                            self.port = listener.port
                            do { self.finishStart(.success(try self.register(self.origin))) }
                            catch { self.finishStart(.failure(error)); self.stop() }
                        case .failed(let error): self.finishStart(.failure(error)); self.stop()
                        case .cancelled: self.finishStart(.failure(CancellationError()))
                        default: break
                        }
                    }
                }
                listener.start(queue: .main)
            }
        } onCancel: { Task { @MainActor [weak self] in self?.stop() } }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        finishStart(.failure(CancellationError()))
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        let active = Array(exchanges.values)
        exchanges.removeAll()
        active.forEach { $0.cancel() }
        resources.removeAll()
        identifiers.removeAll()
        segmentOrder.removeAll()
        pinned.removeAll()
    }

    /// The local address for `url`. `pinned` resources (playlists, keys, maps) stay
    /// addressable for the whole stream; others are media segments, forgotten oldest
    /// first once there are too many. Looking up a known address is constant time, so
    /// refreshing a long playlist costs no more than reading it.
    func register(_ url: URL, pinned isPinned: Bool = true) throws -> URL {
        guard !stopped, let port, SecureTransport.permitsRedirect(from: origin, to: url) else {
            throw HTTPError.secureConnectionRequired
        }
        let identifier: String
        if let existing = identifiers[url] {
            identifier = existing
            if isPinned, !pinned.contains(existing) {
                guard pinned.count < Limits.pinnedResources else { throw HTTPError.invalidResponse }
                segmentOrder.removeAll { $0 == existing }
                pinned.insert(existing)
            }
        } else {
            if isPinned {
                guard pinned.count < Limits.pinnedResources else { throw HTTPError.invalidResponse }
            } else if segmentOrder.count >= Limits.resources {
                let oldest = segmentOrder.removeFirst()
                if let previous = resources.removeValue(forKey: oldest) { identifiers.removeValue(forKey: previous) }
            }
            let suffix = ["m3u8", "mp4", "mov", "ts", "m4s", "aac", "wav", "mp3", "vtt"].contains(url.pathExtension.lowercased()) ? "." + url.pathExtension.lowercased() : ""
            // The secret path already guards access, so short names keep rewritten playlists small.
            identifier = "r\(nextResource)" + suffix
            nextResource += 1
            resources[identifier] = url
            identifiers[url] = identifier
            if isPinned { pinned.insert(identifier) } else { segmentOrder.append(identifier) }
        }
        // No server addresses, credentials or query strings enter local playback URLs.
        return URL(string: "http://\(Limits.host):\(port.rawValue)/\(secret)/\(identifier)")!
    }

    func resource(path: String, host: String) -> URL? {
        guard !stopped, let port, host == "\(Limits.host):\(port.rawValue)" else { return nil }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].isEmpty, parts[1] == secret else { return nil }
        return resources[String(parts[2])]
    }

    func finished(_ id: UUID) { exchanges.removeValue(forKey: id) }

    private func accept(_ connection: NWConnection) {
        guard !stopped, exchanges.count < Limits.connections else { connection.cancel(); return }
        let id = UUID()
        let exchange = LoopbackPlaybackRelayExchange(id: id, connection: connection, relay: self)
        exchanges[id] = exchange
        exchange.start()
    }

    private func finishStart(_ result: Result<URL, any Error>) {
        let continuation = ready
        ready = nil
        continuation?.resume(with: result)
    }
}
