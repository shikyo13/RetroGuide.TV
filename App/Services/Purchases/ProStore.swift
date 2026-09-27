import Foundation
import Observation
import OSLog
import RetroGuideKit
import StoreKit

/// RetroGuide Pro: a one-time purchase that removes ads and unlocks the extras.
/// Bought once, it applies on iPhone, iPad and Apple TV (one app record).
@MainActor
@Observable
final class ProStore {
    enum ProductID {
        static let pro = "com.adamhunt.retroguide.pro"
    }

    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case pending
        case failed(String)
    }

    private(set) var isPro = false
    /// Whether ownership has been checked since launch, so ads never flash up for a Pro owner.
    private(set) var hasLoaded = false
    private(set) var product: Product?
    private(set) var purchaseState = PurchaseState.idle

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "Pro")

    var access: ProAccess {
        ProAccess(isPro: isPro)
    }

    /// Loads the product and current ownership, then keeps watching for
    /// purchases made elsewhere (another device, Ask to Buy, refunds).
    func start() async {
        #if DEBUG
        if DebugLaunchOptions.forcesPro {
            isPro = true
            hasLoaded = true
            return
        }
        #endif
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        await refreshOwnership()
        hasLoaded = true
        await loadProduct()
    }

    func purchase() async {
        guard let product else { return }
        purchaseState = .purchasing
        do {
            switch try await product.purchase() {
            case .success(let verification):
                await handle(verification)
                purchaseState = .idle
            case .pending:
                purchaseState = .pending
            case .userCancelled:
                purchaseState = .idle
            @unknown default:
                purchaseState = .idle
            }
        } catch {
            logger.error("Purchase failed: \(error.localizedDescription, privacy: .public)")
            purchaseState = .failed(error.localizedDescription)
        }
    }

    /// Asks the App Store to re-sync purchases (after a reinstall or on a new device).
    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            logger.error("Restore failed: \(error.localizedDescription, privacy: .public)")
        }
        await refreshOwnership()
    }

    private func loadProduct() async {
        do {
            product = try await Product.products(for: [ProductID.pro]).first
        } catch {
            logger.error("Couldn't load products: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func refreshOwnership() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, Self.grantsPro(transaction) {
                owned = true
            }
        }
        isPro = owned
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result, transaction.productID == ProductID.pro else { return }
        await transaction.finish()
        await refreshOwnership()
    }

    private static func grantsPro(_ transaction: Transaction) -> Bool {
        transaction.productID == ProductID.pro && transaction.revocationDate == nil
    }
}
