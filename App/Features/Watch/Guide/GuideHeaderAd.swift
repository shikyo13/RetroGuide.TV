import SwiftUI

extension EnvironmentValues {
    /// Free version, iPhone in landscape: the guide header carries the ad banner
    /// (in place of the clock) so the channel grid keeps the screen's height.
    @Entry var showsGuideHeaderAd = false
}

#if os(iOS)
import GoogleMobileAds

/// The standard 320×50 banner, sized to sit in the guide header.
struct GuideHeaderAd: View {
    /// Header width needed for the brand, the banner and the buttons side by side.
    static let minimumHeaderWidth: CGFloat = 700

    var body: some View {
        let size = cgSize(for: AdSizeBanner)
        BannerAdView(adSize: AdSizeBanner)
            .frame(width: size.width, height: size.height)
            .clipped()
            // Never resized frame by frame (see FreeVersionAds).
            .transition(.identity)
            .transaction { $0.animation = nil }
    }
}
#endif
