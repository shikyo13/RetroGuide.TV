import RetroGuideKit
import SwiftUI

/// Asks before connecting to a home or VPN Jellyfin server that only offers
/// plain HTTP: two short facts, then the choice.
struct JellyfinPlainHTTPStepView: View {
    private enum Layout {
        static let columnWidth = PlatformMetric.value(tv: CGFloat(1_000), touch: 520)
    }

    let address: URL
    let onConnect: () -> Void
    let onBack: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text("Connect without encryption?")
                .font(Typography.title)
                .foregroundStyle(theme.textPrimary)
            Text("The server at \(JellyfinConnectionText.short(address)) doesn't use HTTPS.")
                .secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                fact("house", "Works at home, and away over a VPN like Tailscale.")
                fact("lock.open", "Your password and video aren't encrypted on that network.")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DesignTokens.Spacing.md) { actions }
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) { actions }
            }
            Text("You can add HTTPS later. See retroguide.tv/support.")
                .font(Typography.caption)
                .foregroundStyle(theme.textSecondary)
        }
        .columnWidth(Layout.columnWidth, alignment: .leading)
    }

    @ViewBuilder
    private var actions: some View {
        Button("Connect Anyway", systemImage: "link", action: onConnect)
            .buttonStyle(.retroPrimary)
            .fixedSize()
        Button("Back", action: onBack)
            .buttonStyle(.retro)
            .fixedSize()
    }

    private func fact(_ systemImage: String, _ text: LocalizedStringKey) -> some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(theme.accentSecondary)
        }
        .font(Typography.body)
        .foregroundStyle(theme.textPrimary)
    }
}
