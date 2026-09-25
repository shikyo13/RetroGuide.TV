import SwiftUI

/// Shown for the brief moment while cached channels load.
struct SplashView: View {
    var body: some View {
        ZStack {
            StaticNoiseView()
                .opacity(DesignTokens.Opacity.subtle)
            BrandMark(size: .large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .crtEffect()
    }
}
