import SwiftUI

/// A recoverable, full-screen error with a retry action.
struct FailureView: View {
    private enum Layout {
        static let contentWidth = PlatformMetric.value(tv: CGFloat(1_000), touch: 560)
    }

    let message: String
    var isCancelled = false
    let retry: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: isCancelled ? "pause.circle" : "antenna.radiowaves.left.and.right.slash")
                .font(Typography.display)
                .foregroundStyle(theme.accent)
            Text(isCancelled ? "Channel loading cancelled" : "We're experiencing technical difficulties")
                .font(Typography.title)
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(Typography.body)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try Again", action: retry)
                .buttonStyle(.retroPrimary)
        }
        .columnWidth(Layout.contentWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .crtEffect()
    }
}
