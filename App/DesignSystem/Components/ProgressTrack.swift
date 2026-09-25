import SwiftUI

/// Thin horizontal progress bar.
struct ProgressTrack: View {
    let progress: Double
    var height: CGFloat = DesignTokens.Spacing.xs
    var tint: Color?

    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.textPrimary.opacity(DesignTokens.Opacity.subtle))
                Capsule()
                    .fill(tint ?? theme.accent)
                    .frame(width: proxy.size.width * min(max(progress, .zero), 1))
            }
        }
        .frame(height: height)
    }
}
