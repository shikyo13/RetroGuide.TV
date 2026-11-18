import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Shown while finding a Jellyfin server waits for local network access:
/// behind the system's question the first time, or when it's turned off.
/// Setup carries on by itself once access is allowed.
struct LocalNetworkStepView: View {
    private enum Layout {
        static let columnWidth = PlatformMetric.value(tv: CGFloat(1_000), touch: 520)
    }

    let onEnterAddress: () -> Void
    let onCancel: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text("Allow Local Network Access")
                .font(Typography.title)
                .foregroundStyle(theme.textPrimary)
            Text("To find your Jellyfin server at home, RetroGuide.TV needs to reach devices on your network. Choose Allow when asked.")
                .secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            Text("Turned it off? In Settings, open RetroGuide.TV and turn on Local Network.")
                .secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DesignTokens.Spacing.md) { actions }
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) { actions }
            }
        }
        .columnWidth(Layout.columnWidth, alignment: .leading)
    }

    @ViewBuilder
    private var actions: some View {
        #if os(iOS)
        if let settings = URL(string: UIApplication.openSettingsURLString) {
            Button("Open Settings", systemImage: "gear") { openURL(settings) }
                .buttonStyle(.retroPrimary)
                .fixedSize()
        }
        #endif
        Button("Enter Address", systemImage: "keyboard", action: onEnterAddress)
            .buttonStyle(.retro)
            .fixedSize()
        Button("Cancel", action: onCancel)
            .buttonStyle(.retro)
            .fixedSize()
    }
}
