import SwiftUI

extension EnvironmentValues {
    /// Free version, iPhone in landscape: the guide header carries the ad banner
    /// (in place of the clock) so the channel grid keeps the screen's height.
    @Entry var showsGuideHeaderAd = false
}

#if os(iOS)
import GoogleMobileAds

/// The standard 320×50 banner, sized to sit in the guide header.
///
/// The header holds an empty ``GuideHeaderAdSlot``; the guide places the ad
/// over that slot after the menu's CRT scanlines, so nothing draws on the ad.
struct GuideHeaderAd: View {
    /// Header width needed for the TV glyph, the banner and the buttons side by side.
    static let minimumHeaderWidth: CGFloat = 600
    /// Header width that also fits the full wordmark next to the banner.
    static let wordmarkHeaderWidth: CGFloat = 760

    static var size: CGSize {
        AdSizeBanner.size
    }

    var body: some View {
        BannerAdView(adSize: AdSizeBanner)
            .frame(width: Self.size.width, height: Self.size.height)
            // Never resized frame by frame (see FreeVersionAds).
            .transition(.identity)
            .transaction { $0.animation = nil }
    }
}

/// Where the guide header's banner goes.
struct GuideHeaderAdSlot: View {
    var body: some View {
        Color.clear
            .frame(width: GuideHeaderAd.size.width, height: GuideHeaderAd.size.height)
            .anchorPreference(key: GuideHeaderAdSlotKey.self, value: .bounds) { $0 }
    }
}

struct GuideHeaderAdSlotKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

extension View {
    /// Shows the guide header's banner over its slot, above everything
    /// drawn before this modifier (the CRT scanlines).
    func guideHeaderAd() -> some View {
        overlayPreferenceValue(GuideHeaderAdSlotKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    let slot = proxy[anchor]
                    GuideHeaderAd()
                        .position(x: slot.midX, y: slot.midY)
                }
            }
        }
    }
}
#endif
