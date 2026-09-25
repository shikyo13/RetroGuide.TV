import RetroGuideKit
import SwiftUI

/// Turns whole groups of automatic channels on or off.
struct ChannelGroupsView: View {
    /// Groups the user may switch off. Custom channels always stay.
    private static let toggleableSources: [ChannelSource] = [.curated, .decade, .library, .network, .collection, .series]

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        SettingsPage(title: "Channel Groups") {
            Text("Choose which kinds of channels are built automatically from your library. Your own channels are always kept.")
                .font(Typography.body)
                .foregroundStyle(theme.textSecondary)
            VStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(Self.toggleableSources, id: \.self) { source in
                    let isEnabled = !app.customization.disabledSources.contains(source)
                    CheckmarkRow(title: source.displayName, detail: detail(for: source), isSelected: isEnabled) {
                        app.setSource(source, enabled: !isEnabled)
                    }
                }
            }
        }
    }

    private func detail(for source: ChannelSource) -> String {
        let count = app.lineup.filter { $0.definition.source == source }.count
        return count == 1 ? "1 channel" : "\(count) channels"
    }
}
