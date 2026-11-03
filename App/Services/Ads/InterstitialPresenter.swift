#if os(iOS)
import GoogleMobileAds
import UIKit

/// Reports when a full-screen ad has gone away, whether it was closed or
/// failed to appear, so live TV can come back.
@MainActor
final class InterstitialPresenter: NSObject, FullScreenContentDelegate {
    private var currentAd: (any CachedInterstitial)?
    private var onImpression: (() -> Void)?
    private var onFinish: ((Bool) -> Void)?
    private var recordedImpression = false

    var isPresenting: Bool { currentAd != nil }

    /// Check readiness before suspending playback. Retain the ad until its terminal callback.
    func present(
        _ ad: any CachedInterstitial,
        from controller: UIViewController,
        onPresent: () -> Void,
        onImpression: @escaping () -> Void,
        onFinish: @escaping (Bool) -> Void
    ) throws {
        guard !isPresenting else { return }
        try ad.canPresent(from: controller)
        currentAd = ad
        recordedImpression = false
        self.onImpression = onImpression
        self.onFinish = onFinish
        ad.fullScreenContentDelegate = self
        onPresent()
        ad.present(from: controller)
    }

    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        guard owns(ad), !recordedImpression else { return }
        recordedImpression = true
        let handler = onImpression
        onImpression = nil
        handler?()
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        guard owns(ad) else { return }
        finish()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        guard owns(ad) else { return }
        finish()
    }

    private func owns(_ ad: FullScreenPresentingAd) -> Bool {
        (ad as AnyObject) === currentAd
    }

    private func finish() {
        let handler = onFinish
        let displayed = recordedImpression
        currentAd?.fullScreenContentDelegate = nil
        currentAd = nil
        onImpression = nil
        onFinish = nil
        handler?(displayed)
    }
}
#endif
