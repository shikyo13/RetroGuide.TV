import RetroTVKit
import SwiftUI

/// A single program block in the guide grid.
struct GuideProgramCell: View {
    let program: ScheduledProgram
    let scale: GuideTimeScale
    let now: Date
    let isFocused: Bool

    @Environment(\.theme) private var theme

    var body: some View {
        let width = max(scale.width(from: program.start, to: program.slotEnd) - GuideLayout.cellSpacing, .zero)
        HStack(spacing: DesignTokens.Spacing.xs) {
            Rectangle()
                .fill(theme.color(for: program.item.audience))
                .frame(width: GuideLayout.audienceStripeWidth)
            if startsBeforeWindow {
                Image(systemName: "arrowtriangle.left.fill")
                    .font(Typography.micro)
            }
            if width >= GuideLayout.minimumTitleWidth {
                labels(showsSubtitle: width >= GuideLayout.minimumSubtitleWidth)
            }
            Spacer(minLength: .zero)
            if endsAfterWindow {
                Image(systemName: "arrowtriangle.right.fill")
                    .font(Typography.micro)
                    .padding(.trailing, DesignTokens.Spacing.xs)
            }
        }
        .foregroundStyle(isFocused ? theme.textOnFocus : textColor)
        .frame(width: width, height: GuideLayout.rowHeight, alignment: .leading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous))
        .shadow(
            color: .black.opacity(isFocused ? DesignTokens.Shadow.opacity : .zero),
            radius: DesignTokens.Shadow.radius
        )
        .zIndex(isFocused ? 1 : .zero)
    }

    private func labels(showsSubtitle: Bool) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.hairline) {
            Text(program.item.headline)
                .font(Typography.bodyEmphasis)
                .lineLimit(1)
            if showsSubtitle, let subheadline = program.item.subheadline {
                Text(subheadline)
                    .font(Typography.caption)
                    .opacity(DesignTokens.Opacity.strong)
                    .lineLimit(1)
            }
        }
    }

    private var startsBeforeWindow: Bool {
        program.start < scale.window.start
    }

    private var endsAfterWindow: Bool {
        program.slotEnd > scale.window.end
    }

    private var isAiring: Bool {
        program.contains(now)
    }

    private var hasEnded: Bool {
        program.slotEnd <= now
    }

    private var textColor: Color {
        hasEnded ? theme.textSecondary : theme.textPrimary
    }

    private var background: Color {
        if isFocused { return theme.focusFill }
        if isAiring { return theme.surfaceRaised }
        return theme.surface.opacity(hasEnded ? DesignTokens.Opacity.muted : DesignTokens.Opacity.strong)
    }
}
