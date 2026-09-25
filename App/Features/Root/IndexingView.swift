import RetroGuideKit
import SwiftUI

/// Full-screen progress while the library is indexed for the first time.
struct IndexingView: View {
    private enum Layout {
        static let contentWidth: CGFloat = 900
        static let progressHeight: CGFloat = 14
    }

    let progress: LibraryLoadProgress

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            BrandMark(size: .large)
            VStack(spacing: DesignTokens.Spacing.md) {
                Text("Programming your channels")
                    .font(Typography.headline)
                    .foregroundStyle(theme.textPrimary)
                ProgressTrack(progress: progress.fraction, height: Layout.progressHeight)
                    .animation(DesignTokens.Motion.standardEase, value: progress.fraction)
                Text(progress.message)
                    .font(Typography.callout)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(width: Layout.contentWidth)
            .panel(padding: DesignTokens.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .crtEffect()
    }
}
