import Foundation
import RetroGuideKit
import StoreKit
#if os(iOS)
import AdServices
#endif

actor AttributionDelivery {
    private enum Settings {
        static let requestTimeout: TimeInterval = 20
        static let resourceTimeout: TimeInterval = 45
        static let maximumResponseBytes = 4096
    }
    private let endpoint: URL
    private let identity: AttributionIdentity
    private let outbox: PurchaseOutbox
    private let session: URLSession
    private var worker: Task<Void, Never>?
    private var registered = false
    private var attributionResolved = false
    private var revision = 0

    init(endpoint: URL, identity: AttributionIdentity) {
        self.endpoint = endpoint
        self.identity = identity
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        outbox = PurchaseOutbox(file: directory.appendingPathComponent("Attribution/purchases.json"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Settings.requestTimeout
        configuration.timeoutIntervalForResource = Settings.resourceTimeout
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: AttributionRedirectPolicy(), delegateQueue: nil)
    }

    func enqueue(_ record: PurchaseOutbox.Record) async {
        await outbox.enqueue(record)
        revision += 1
        kick()
    }

    func kick() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            await self?.run()
        }
    }

    private func run() async {
        defer { worker = nil }
        for attempt in 0..<PurchaseOutbox.Limits.attempts {
            let deliveryRevision = revision
            if Task.isCancelled { return }
            do {
                if !registered || !attributionResolved { try await register() }
            } catch { }
            let delivered: Bool
            if registered {
                delivered = await outbox.drain { [weak self] record in
                    guard let self else { throw URLError(.cancelled) }
                    _ = try await self.post(path: "purchases", payload: ["signedTransaction": record.signedTransaction])
                }
            } else {
                delivered = false
            }
            if delivered && attributionResolved && deliveryRevision == revision { return }
            if attempt < PurchaseOutbox.Limits.retrySeconds.count {
                try? await Task.sleep(for: .seconds(PurchaseOutbox.Limits.retrySeconds[attempt]))
            }
        }
    }

    private func register() async throws {
        let appResult = try await AppTransaction.shared
        guard case .verified = appResult else { throw URLError(.userAuthenticationRequired) }
        // Register independently so AdServices failure never blocks purchase ingestion.
        if !registered {
            let data = try await post(path: nil, payload: ["signedAppTransaction": appResult.jwsRepresentation])
            attributionResolved = try JSONDecoder().decode(RegistrationResponse.self, from: data).attributionResolved
            registered = true
        }
        if attributionResolved { return }
        #if os(iOS)
        let token = try AAAttribution.attributionToken()
        let data = try await post(path: nil, payload: [
            "signedAppTransaction": appResult.jwsRepresentation,
            "attributionToken": token
        ])
        attributionResolved = try JSONDecoder().decode(RegistrationResponse.self, from: data).attributionResolved
        #else
        attributionResolved = true
        #endif
    }

    private func post(path: String?, payload: [String: String]) async throws -> Data {
        var url = endpoint.appendingPathComponent("v1/installations/\(identity.id.uuidString.lowercased())")
        if let path { url.appendPathComponent(path) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(identity.secret)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < Settings.maximumResponseBytes else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }

    private struct RegistrationResponse: Decodable { let attributionResolved: Bool }
}

private final class AttributionRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
