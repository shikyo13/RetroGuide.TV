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
        /// The App Store approved a purchase but its signature didn't check out.
        case unverified
        case restoring
        case restored
        case nothingToRestore
        case restoreFailed(String)
    }

    private(set) var isPro = false
    /// Whether ownership has been checked since launch, so ads never flash up for a Pro owner.
    private(set) var hasLoaded = false
    private(set) var product: Product?
    private(set) var isLoadingProduct = false
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
        PurchaseAttribution.shared.start()
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
        record(.started)
        do {
            var options: Set<Product.PurchaseOption> = []
            if let token = PurchaseAttribution.shared.accountToken {
                options.insert(.appAccountToken(token))
            }
            switch try await product.purchase(options: options) {
            case .success(let verification):
                let verified = await handle(verification)
                purchaseState = verified ? .idle : .unverified
                record(verified ? .completed : .unverified)
            case .pending:
                purchaseState = .pending
                record(.pending)
            case .userCancelled:
                purchaseState = .idle
                record(.cancelled)
            @unknown default:
                purchaseState = .idle
            }
        } catch {
            logger.error("Purchase failed: \(error.localizedDescription, privacy: .public)")
            purchaseState = .failed(error.localizedDescription)
            record(.failed)
        }
    }

    private func record(_ step: UsageEvent.PurchaseStep) {
        PurchaseAttribution.shared.record(UsageEvent(.proPurchase, detail: step.rawValue))
    }

    /// Asks the App Store to re-sync purchases (after a reinstall or on a new device),
    /// and says what came of it.
    func restore() async {
        purchaseState = .restoring
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            // The viewer closed the Apple Account sign-in: nothing to report.
            purchaseState = .idle
            return
        } catch {
            logger.error("Restore failed: \(error.localizedDescription, privacy: .public)")
            await refreshOwnership()
            // Already owned on this device: nothing was lost, so don't report a failure.
            purchaseState = isPro ? .restored : .restoreFailed(error.localizedDescription)
            return
        }
        await refreshOwnership()
        purchaseState = isPro ? .restored : .nothingToRestore
    }

    /// Loads the product if an earlier try failed (no network at launch),
    /// e.g. when the upgrade screen opens.
    func loadProductIfNeeded() async {
        guard product == nil, !isLoadingProduct else { return }
        await loadProduct()
    }

    private func loadProduct() async {
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        do {
            product = try await Product.products(for: [ProductID.pro]).first
        } catch {
            logger.error("Couldn't load products: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func refreshOwnership() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            PurchaseAttribution.shared.record(result)
            if case .verified(let transaction) = result, Self.grantsPro(transaction) {
                owned = true
            }
        }
        isPro = owned
    }

    /// Applies a purchase; `false` if its signature didn't verify (Pro stays locked).
    @discardableResult
    private func handle(_ result: VerificationResult<Transaction>) async -> Bool {
        guard case .verified(let transaction) = result else { return false }
        guard transaction.productID == ProductID.pro else { return true }
        PurchaseAttribution.shared.record(result)
        await transaction.finish()
        await refreshOwnership()
        return true
    }

    private static func grantsPro(_ transaction: Transaction) -> Bool {
        transaction.productID == ProductID.pro && transaction.revocationDate == nil
    }
}
