import RetroGuideKit
import SwiftUI

/// Every channel in one list: find one, show only favorites or hidden ones,
/// and star or hide a channel from its row. A row opens the channel's page.
struct ChannelManagerView: View {
    private enum Filter: Hashable {
        case all, favorites, hidden
    }

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var query = ""
    @State private var filter = Filter.all

    var body: some View {
        SettingsPage(title: String(localized: "Channels")) {
            TextField("Find a channel", text: $query)
                .font(Typography.settingsBody)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .frame(minHeight: DesignTokens.Control.minimumHeight)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.medium))
            filters
            ForEach(ChannelSource.allCases, id: \.self) { source in
                let channels = matching.filter { $0.definition.source == source }
                if !channels.isEmpty {
                    SettingsSection(source.displayName) {
                        LazyVStack(spacing: DesignTokens.Spacing.sm) {
                            ForEach(channels) { channel in
                                ChannelListRow(channel: channel)
                            }
                        }
                    }
                }
            }
            if matching.isEmpty {
                Text(query.isEmpty ? String(localized: "No channels here yet.") : String(localized: "No matching channels"))
                    .font(Typography.settingsBody)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                chip(String(localized: "All \(app.lineup.count)"), .all)
                if app.pro.isPro {
                    chip(String(localized: "Favorites \(app.lineup.filter(app.viewing.isFavorite).count)"), .favorites)
                }
                chip(String(localized: "Hidden \(app.lineup.filter(\.isHidden).count)"), .hidden)
            }
        }
        .scrollClipDisabled()
    }

    private func chip(_ title: String, _ value: Filter) -> some View {
        Button(title) { filter = value }
            .buttonStyle(filter == value ? .retroPrimary : .retro)
    }

    private var matching: [Channel] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return app.lineup.filter { channel in
            switch filter {
            case .all: break
            case .favorites: guard app.viewing.isFavorite(channel) else { return false }
            case .hidden: guard channel.isHidden else { return false }
            }
            return search.isEmpty || channel.name.localizedCaseInsensitiveContains(search)
                || channel.callSign.localizedCaseInsensitiveContains(search) || String(channel.number) == search
        }
    }
}

/// A channel's row: number, name and size open its page; the star and the eye
/// favorite and hide it in place.
private struct ChannelListRow: View {
    let channel: Channel

    @Environment(AppModel.self) private var app
    @State private var showsUpgrade = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            NavigationLink {
                ChannelDetailView(channelID: channel.id)
            } label: {
                ChannelRowLabel(channel: channel)
            }
            Button {
                if app.pro.isPro { app.viewing.toggleFavorite(channel) } else { showsUpgrade = true }
            } label: {
                Label(isFavorite ? String(localized: "Remove favorite") : String(localized: "Add favorite"),
                      systemImage: isFavorite ? "star.fill" : "star")
                    .labelStyle(.iconOnly)
            }
            .channelRowIconStyle()
            Button {
                app.setHidden(!channel.isHidden, channelID: channel.id)
            } label: {
                Label(channel.isHidden ? String(localized: "Show in guide") : String(localized: "Hide from guide"),
                      systemImage: channel.isHidden ? "eye.slash" : "eye")
                    .labelStyle(.iconOnly)
            }
            .channelRowIconStyle()
        }
        .appSheet(isPresented: $showsUpgrade) { ProUpgradeView() }
    }

    private var isFavorite: Bool { app.viewing.isFavorite(channel) }
}

/// Channel number, name and size for list rows.
struct ChannelRowLabel: View {
    let channel: Channel

    @Environment(\.theme) private var theme
    @Environment(\.rowIsFocused) private var rowIsFocused

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Text(String(channel.number))
                .font(Typography.channelNumber)
                .frame(width: DesignTokens.Spacing.xxl, alignment: .trailing)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.hairline) {
                Text(channel.name)
                    .lineLimit(1)
                Text(detail)
                    .secondaryText()
                    .lineLimit(1)
            }
            Spacer(minLength: DesignTokens.Spacing.sm)
        }
        .opacity(channel.isHidden && !rowIsFocused ? DesignTokens.Opacity.muted : 1)
    }

    private var detail: String {
        let size = String(localized: "\(channel.items.count) programs · \(ScheduleFormatting.hours(channel.totalRuntime))")
        return channel.isHidden ? String(localized: "Hidden from guide") + " · " + size : size
    }
}

private extension View {
    /// Round icons on iPhone and iPad; focusable capsules on Apple TV.
    @ViewBuilder
    func channelRowIconStyle() -> some View {
        #if os(tvOS)
        buttonStyle(.retro)
        #else
        buttonStyle(.retroIcon)
        #endif
    }
}
