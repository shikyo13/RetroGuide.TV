#if os(iOS)
import GoogleMobileAds
import SwiftUI

/// A banner ad of exactly `adSize`.
///
/// SwiftUI sizes a plain container; the banner inside keeps its own frame at
/// the ad size. Letting SwiftUI resize the banner itself made the SDK load
/// creatives for a different size, which then showed cropped.
struct BannerAdView: UIViewRepresentable {
    let adSize: AdSize

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        let banner = BannerView(adSize: adSize)
        banner.adUnitID = AdUnits.banner
        banner.rootViewController = PresentingViewController.current
        banner.frame = CGRect(origin: .zero, size: adSize.size)
        container.addSubview(banner)
        context.coordinator.banner = banner
        banner.load(AdRequestFactory.make())
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        guard let banner = context.coordinator.banner, !isAdSizeEqualToSize(size1: banner.adSize, size2: adSize) else { return }
        banner.adSize = adSize
        banner.frame = CGRect(origin: .zero, size: adSize.size)
        banner.load(AdRequestFactory.make())
    }

    final class Coordinator {
        var banner: BannerView?
    }

    /// Google's anchored adaptive banner for the screen's width: the height
    /// that suits the device, which creatives are made to fill.
    static func adSize(fitting width: CGFloat) -> AdSize {
        currentOrientationAnchoredAdaptiveBanner(width: width)
    }
}
#endif
