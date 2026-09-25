import RetroGuideKit
import SwiftUI

/// Finds shows and movies in the lineup with results that update as you type.
/// Live TV keeps playing picture-in-picture in the bottom-right corner.
struct SearchView: View {
    private enum Layout {
        static let resultsWidth: CGFloat = 1_150
    }

    private enum Timing {
        /// Brief pause after a keystroke before searching, so fast typing stays smooth.
        static let debounce: Duration = .milliseconds(150)
    }

    let onClose: () -> Void
    let onTune: (Channel) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var query = ""
    @State private var results: [SearchResult] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    ForEach(results) { result in
                        Button {
                            if let channel = result.channel { onTune(channel) }
                        } label: {
                            SearchResultRow(result: result)
                        }
                        .buttonStyle(.retroRow)
                    }
                    if results.isEmpty {
                        Text(query.isEmpty ? "Search every show and movie on your channels." : "Nothing on your channels matches \u{201C}\(query)\u{201D}.")
                            .font(Typography.body)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                .frame(width: Layout.resultsWidth, alignment: .leading)
                .padding(.vertical, DesignTokens.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollClipDisabled()
            .searchable(text: $query, prompt: "Shows and movies")
            .screenBackground()
            .crtEffect()
        }
        .onExitCommand(perform: onClose)
        .task(id: query) {
            try? await Task.sleep(for: Timing.debounce)
            guard !Task.isCancelled else { return }
            results = app.searchIndex.search(query, at: .now)
        }
    }
}
