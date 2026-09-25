import RetroGuideKit
import SwiftUI

/// Every channel in the lineup, grouped by where it came from.
struct ChannelManagerView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        SettingsPage(title: "Channels") {
            ForEach(ChannelSource.allCases, id: \.self) { source in
                let channels = app.lineup.filter { $0.definition.source == source }
                if !channels.isEmpty {
                    SettingsSection(source.displayName) {
                        LazyVStack(spacing: DesignTokens.Spacing.sm) {
                            ForEach(channels) { channel in
                                NavigationLink {
                                    ChannelDetailView(channelID: channel.id)
                                } label: {
                                    ChannelRowLabel(channel: channel)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Channel number, name, size and visibility for list rows.
struct ChannelRowLabel: View {
    let channel: Channel

    @Environment(\.theme) private var theme
    @Environment(\.rowIsFocused) private var rowIsFocused
    /// iPhone in portrait: the size goes under the name so the name isn't cut off.
    @Environment(\.isNarrowLayout) private var isNarrowLayout

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Text(String(channel.number))
                .font(Typography.channelNumber)
                .frame(width: DesignTokens.Spacing.xxl, alignment: .trailing)
            if isNarrowLayout {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.hairline) {
                    name
                    size
                }
                Spacer(minLength: DesignTokens.Spacing.md)
            } else {
                name
                Spacer(minLength: DesignTokens.Spacing.md)
                size
            }
            Image(systemName: channel.isHidden ? "eye.slash" : "eye")
                .secondaryText()
        }
        .opacity(channel.isHidden && !rowIsFocused ? DesignTokens.Opacity.muted : 1)
    }

    private var name: some View {
        Text(channel.name)
            .lineLimit(1)
    }

    private var size: some View {
        Text("\(channel.items.count) programs · \(ScheduleFormatting.hours(channel.totalRuntime))")
            .secondaryText()
            .lineLimit(1)
    }
}
