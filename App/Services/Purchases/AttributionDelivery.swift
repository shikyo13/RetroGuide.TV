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
    private let usage: UsageLedger
    private let client: UsageClient
    private let session: URLSession
    private var worker: Task<Void, Never>?
    private var registered = false
    private var attributionResolved = false
    private var revision = 0

    init(endpoint: URL, identity: AttributionIdentity, client: UsageClient) {
        self.endpoint = endpoint
        self.identity = identity
        self.client = client
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        outbox = PurchaseOutbox(file: directory.appendingPathComponent("Attribution/purchases.json"))
        usage = UsageLedger(file: directory.appendingPathComponent("Attribution/usage.json"))
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

    func record(_ event: UsageEvent) async {
        guard await usage.record(event) else { return }
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
            var delivered = false
            if registered {
                let purchases = await outbox.drain { [weak self] record in
                    guard let self else { throw URLError(.cancelled) }
                    do {
                        _ = try await self.post(path: "purchases", payload: ["signedTransaction": record.signedTransaction])
                    } catch let failure as HTTPFailure where failure.rejectsRecord {
                        throw PurchaseOutbox.Rejected()
                    }
                }
                let context = await UsageContext.current()
                let events = await usage.drain { [weak self] batch in
                    guard let self else { throw URLError(.cancelled) }
                    do {
                        let payload = UsageBatch(client: client, context: context, events: batch)
                        _ = try await self.post(path: "usage", payload: payload)
                    } catch let failure as HTTPFailure where failure.isPermanent {
                        throw UsageLedger.Rejected()
                    }
                }
                delivered = purchases && events
            }
            if delivered && attributionResolved && deliveryRevision == revision { return }
            if attempt < PurchaseOutbox.Limits.retrySeconds.count {
                try? await Task.sleep(for: .seconds(PurchaseOutbox.Limits.retrySeconds[attempt]))
            }
        }
    }

    /// The App Store's signed record of this app, which registration requires.
    private func signedAppTransaction() async throws -> String {
        #if DEBUG
        if DebugLaunchOptions.attributionURL != nil {
            // A local test server: simulator and Xcode builds have no App Store signature.
            return (try? await AppTransaction.shared.jwsRepresentation) ?? "debug-unsigned-app-transaction"
        }
        #endif
        let appResult = try await AppTransaction.shared
        guard case .verified = appResult else { throw URLError(.userAuthenticationRequired) }
        return appResult.jwsRepresentation
    }

    private func register() async throws {
        let appTransaction = try await signedAppTransaction()
        // Register independently so AdServices failure never blocks purchase ingestion.
        if !registered {
            let data = try await post(path: nil, payload: ["signedAppTransaction": appTransaction])
            attributionResolved = try JSONDecoder().decode(RegistrationResponse.self, from: data).attributionResolved
            registered = true
        }
        if attributionResolved { return }
        #if os(iOS)
        let token = try AAAttribution.attributionToken()
        let data = try await post(path: nil, payload: [
            "signedAppTransaction": appTransaction,
            "attributionToken": token
        ])
        attributionResolved = try JSONDecoder().decode(RegistrationResponse.self, from: data).attributionResolved
        #else
        attributionResolved = true
        #endif
    }

    private func post(path: String?, payload: some Encodable) async throws -> Data {
        var url = endpoint.appendingPathComponent("v1/installations/\(identity.id.uuidString.lowercased())")
        if let path { url.appendPathComponent(path) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(identity.secret)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(response.statusCode) else { throw HTTPFailure(status: response.statusCode) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < Settings.maximumResponseBytes else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }

    private struct RegistrationResponse: Decodable { let attributionResolved: Bool }

    /// The service answered with an error status.
    private struct HTTPFailure: Error {
        let status: Int

        /// The request itself is wrong (or unknown to this service):
        /// sending it again won't help.
        var isPermanent: Bool { [400, 404, 409, 413, 422].contains(status) }
        /// The service refused this signed record itself (unverifiable or too large),
        /// not the request path or the installation, so later records can still go.
        var rejectsRecord: Bool { [413, 422].contains(status) }
    }

    private struct UsageBatch: Encodable {
        let platform: String
        let version: String
        let os: String
        let storefront: String?
        let language: String?
        let events: [UsageEvent]

        init(client: UsageClient, context: UsageContext, events: [UsageEvent]) {
            platform = client.platform
            version = client.version
            os = client.os
            storefront = context.storefront
            language = context.language
            self.events = events
        }
    }
}

/// The device type, major system version and app version sent with usage events.
struct UsageClient: Sendable {
    let platform: String
    let version: String
    /// "27" for iOS 27 or tvOS 27.
    let os = String(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
}

/// Where usage comes from, coarsely: the App Store country the person buys from
/// (not the device's location) and the language the app is showing.
struct UsageContext: Sendable {
    /// ISO 3166-1 alpha-3, e.g. "DEU"; the same code Apple signs into purchases.
    let storefront: String?
    /// The app localization in use, e.g. "de" or "pt-BR".
    let language: String?

    static func current() async -> UsageContext {
        UsageContext(storefront: await Storefront.current?.countryCode,
                     language: Bundle.main.preferredLocalizations.first)
    }
}

private final class AttributionRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
