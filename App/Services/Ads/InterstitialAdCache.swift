#if os(iOS)
import GoogleMobileAds
import OSLog
import RetroGuideKit
import UIKit

@MainActor
protocol CachedInterstitial: AnyObject {
    var fullScreenContentDelegate: (any FullScreenContentDelegate)? { get set }
    func canPresent(from rootViewController: UIViewController?) throws
    func present(from rootViewController: UIViewController?)
}

extension InterstitialAd: CachedInterstitial {}

/// Keeps one fresh ad. Cancellation or invalidation discards an in-flight result.
@MainActor
final class InterstitialAdCache {
    private var ad: (any CachedInterstitial)?
    private var policy = InterstitialLoadPolicy()
    private var isLoading = false
    private var generation = 0
    private let load: @MainActor () async throws -> any CachedInterstitial
    private let now: @MainActor () -> Date
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "Ads")

    init(
        now: @escaping @MainActor () -> Date = Date.init,
        load: @escaping @MainActor () async throws -> any CachedInterstitial
    ) {
        self.now = now
        self.load = load
    }

    func refreshIfNeeded() async {
        guard !Task.isCancelled, !isLoading, policy.shouldLoad(at: now()) else { return }
        ad = nil
        isLoading = true
        let requestGeneration = generation
        defer { isLoading = false }
        do {
            let loaded = try await load()
            guard !Task.isCancelled, requestGeneration == generation else { return }
            ad = loaded
            policy.loaded(at: now())
        } catch {
            guard !Task.isCancelled, requestGeneration == generation else { return }
            policy.failed(at: now())
            logger.error("Full-screen ad failed to load: \(error.localizedDescription, privacy: .public)")
        }
    }

    func takeFreshAd() -> (any CachedInterstitial)? {
        let fresh = policy.isFresh(at: now()) ? ad : nil
        ad = nil
        policy.discard()
        return fresh
    }

    func presentationFailed() {
        policy.failed(at: now())
    }

    func discard() {
        generation += 1
        ad = nil
        policy.discard()
    }
}
#endif
