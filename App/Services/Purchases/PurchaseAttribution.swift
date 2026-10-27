import Foundation
import RetroGuideKit
import Security
import StoreKit
#if os(iOS)
import AdServices
#endif

/// Optional first-party measurement. No analytics request is awaited by ProStore.
@MainActor
final class PurchaseAttribution {
    static let shared = PurchaseAttribution()
    let accountToken: UUID?
    private let delivery: AttributionDelivery?

    private init() {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "RetroGuideAttributionURL") as? String,
              let endpoint = URL(string: raw), endpoint.scheme == "https",
              endpoint.host != nil, endpoint.user == nil, endpoint.password == nil,
              endpoint.query == nil, endpoint.fragment == nil else {
            accountToken = nil
            delivery = nil
            return
        }
        let keychain = KeychainStore(service: "com.adamhunt.retroguide.attribution")
        let identity: AttributionIdentity
        if let saved = keychain.token(for: "installation"),
           let data = saved.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(AttributionIdentity.self, from: data) {
            identity = decoded
        } else {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                accountToken = nil
                delivery = nil
                return
            }
            identity = AttributionIdentity(id: UUID(), secret: bytes.map { String(format: "%02x", $0) }.joined())
            guard let data = try? JSONEncoder().encode(identity),
                  let encoded = String(data: data, encoding: .utf8),
                  keychain.setToken(encoded, for: "installation") else {
                accountToken = nil
                delivery = nil
                return
            }
        }
        accountToken = identity.id
        delivery = AttributionDelivery(endpoint: endpoint, identity: identity)
    }

    func start() {
        guard let delivery else { return }
        Task { await delivery.kick() }
    }

    func record(_ result: VerificationResult<Transaction>) {
        guard let delivery, case .verified(let transaction) = result,
              transaction.productID == ProStore.ProductID.pro else { return }
        let record = PurchaseOutbox.Record(id: "\(transaction.environment)-\(transaction.id)",
                                          signedTransaction: result.jwsRepresentation)
        Task { await delivery.enqueue(record) }
    }
}

struct AttributionIdentity: Codable, Sendable {
    let id: UUID
    let secret: String
}
