import RetroGuideKit
import SwiftUI

/// A search result: poster, title, and when/where it airs next.
struct SearchResultRow: View {
    private enum Layout {
        static let posterWidth: CGFloat = 64
        static let posterHeight: CGFloat = 96
    }

    let result: SearchResult

    @Environment(\.theme) private var theme
    @Environment(\.rowIsFocused) private var rowIsFocused

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            RemoteImage(serverID: result.title.sample.serverID, reference: result.title.sample.artwork.poster, size: ArtworkSize.poster) {
                theme.surfaceRaised
            }
            .frame(width: Layout.posterWidth, height: Layout.posterHeight)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.small))
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(result.title.title)
                    .font(Typography.bodyEmphasis)
                    .lineLimit(1)
                Text(airingText)
                    .secondaryText()
                    .lineLimit(1)
            }
            Spacer(minLength: DesignTokens.Spacing.md)
            if let channel = result.channel {
                Text("\(channel.number) \(channel.callSign)")
                    .font(Typography.callSign)
                    .secondaryText()
            }
        }
    }

    private var airingText: String {
        let now = Date.now
        guard let airing = result.airing, let channel = result.channel else {
            return result.title.kind == .movie ? "Movie" : "Show"
        }
        if airing.contains(now) {
            return "On now · \(channel.name) · \(ScheduleFormatting.remaining(in: airing, at: now))"
        }
        return "Next: \(ScheduleFormatting.dayAndTime(airing.start)) · \(channel.name)"
    }
}
