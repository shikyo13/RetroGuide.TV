#if os(iOS)
import GoogleMobileAds
import SwiftUI

/// A standard mobile banner: 320×50 on iPhone, a 728×90 leaderboard where
/// the screen is wide enough (iPad).
struct BannerAdView: UIViewRepresentable {
    let adSize: AdSize

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: adSize)
        banner.adUnitID = AdUnits.banner
        banner.rootViewController = PresentingViewController.current
        banner.load(AdRequestFactory.make())
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {
        guard !isAdSizeEqualToSize(size1: banner.adSize, size2: adSize) else { return }
        banner.adSize = adSize
        banner.load(AdRequestFactory.make())
    }

    /// The largest standard banner that fits `width`.
    static func adSize(fitting width: CGFloat) -> AdSize {
        width >= cgSize(for: AdSizeLeaderboard).width ? AdSizeLeaderboard : AdSizeBanner
    }
}
#endif
