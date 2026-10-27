#if os(iOS)
import Foundation

/// AdMob ad unit IDs, set per build configuration in Config/Ads.xcconfig and
/// read from Info.plist (Debug builds use Google's test units).
enum AdUnits {
    private enum InfoKey {
        static let banner = "RetroGuideAdMobBannerUnitID"
        static let interstitial = "RetroGuideAdMobInterstitialUnitID"
    }

    static var banner: String? {
        value(for: InfoKey.banner)
    }

    static var interstitial: String? {
        value(for: InfoKey.interstitial)
    }

    private static func value(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else { return nil }
        return value
    }
}
#endif
