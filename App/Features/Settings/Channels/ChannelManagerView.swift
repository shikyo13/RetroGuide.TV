import RetroTVKit
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

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Text(String(channel.number))
                .font(Typography.channelNumber)
                .frame(width: DesignTokens.Spacing.xxl, alignment: .trailing)
            Text(channel.name)
                .lineLimit(1)
            Spacer(minLength: DesignTokens.Spacing.md)
            Text("\(channel.items.count) programs · \(ScheduleFormatting.hours(channel.totalRuntime))")
                .secondaryText()
            Image(systemName: channel.isHidden ? "eye.slash" : "eye")
                .secondaryText()
        }
        .opacity(channel.isHidden && !rowIsFocused ? DesignTokens.Opacity.muted : 1)
    }
}
