import RetroTVKit
import SwiftUI

/// "We'll be right back" card shown in the gap between aligned programs.
struct IntermissionCard: View {
    private enum Layout {
        static let posterWidth: CGFloat = 280
        static let posterHeight: CGFloat = 420
    }

    let channel: Channel
    let program: ScheduledProgram

    @Environment(\.theme) private var theme

    var body: some View {
        let next = channel.timeline.program(after: program)
        ZStack {
            theme.backgroundGradient.ignoresSafeArea()
            VStack(spacing: DesignTokens.Spacing.xl) {
                BrandMark(size: .large)
                Text("We'll be right back")
                    .font(Typography.title)
                    .foregroundStyle(theme.textPrimary)
                if let next {
                    upNext(next)
                }
            }
        }
    }

    private func upNext(_ next: ScheduledProgram) -> some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            RemoteImage(serverID: next.item.serverID, reference: next.item.artwork.poster, size: ArtworkSize.poster) {
                theme.surface
            }
            .frame(width: Layout.posterWidth, height: Layout.posterHeight)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium))
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text("Up next on \(channel.name)")
                    .font(Typography.callout)
                    .foregroundStyle(theme.accentSecondary)
                Text(next.item.headline)
                    .font(Typography.headline)
                    .foregroundStyle(theme.textPrimary)
                if let subheadline = next.item.subheadline {
                    Text(subheadline)
                        .font(Typography.body)
                        .foregroundStyle(theme.textSecondary)
                }
                Text(next.start, style: .timer)
                    .font(Typography.clock)
                    .foregroundStyle(theme.accent)
            }
        }
        .panel()
    }
}
