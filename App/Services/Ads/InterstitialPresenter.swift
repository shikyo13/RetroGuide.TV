#if os(iOS)
import GoogleMobileAds

/// Reports when a full-screen ad has gone away, whether it was closed or
/// failed to appear, so live TV can come back.
@MainActor
final class InterstitialPresenter: NSObject, FullScreenContentDelegate {
    var onFinish: (() -> Void)?

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        finish()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        finish()
    }

    private func finish() {
        let handler = onFinish
        onFinish = nil
        handler?()
    }
}
#endif
