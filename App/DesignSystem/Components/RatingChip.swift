import RetroGuideKit
import SwiftUI

/// Small outlined label showing a content rating, colored by audience.
struct RatingChip: View {
    let rating: String?
    let audience: Audience

    @Environment(\.theme) private var theme

    var body: some View {
        if let label {
            Text(label)
                .font(Typography.micro)
                .foregroundStyle(theme.color(for: audience))
                .padding(.horizontal, DesignTokens.Spacing.xs)
                .padding(.vertical, DesignTokens.Spacing.hairline)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                        .strokeBorder(theme.color(for: audience), lineWidth: DesignTokens.Stroke.thin)
                )
        }
    }

    /// Strips country prefixes such as `"gb/"` for display.
    private var label: String? {
        guard let rating, !rating.isEmpty else { return nil }
        return rating.split(separator: "/").last.map { String($0).uppercased() }
    }
}
