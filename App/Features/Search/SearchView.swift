import RetroGuideKit
import SwiftUI

/// Finds shows and movies in the lineup with results that update as you type.
/// Live TV keeps playing picture-in-picture in the bottom-right corner.
struct SearchView: View {
    private enum Layout {
        static let resultsWidth = PlatformMetric.value(tv: CGFloat(1_150), touch: 720)
        /// Left on Apple TV beside the picture-in-picture window; centered on touch screens.
        static let columnAlignment = PlatformMetric.value(tv: Alignment.leading, touch: .center)
    }

    private enum Timing {
        /// Brief pause after a keystroke before searching, so fast typing stays smooth.
        static let debounce: Duration = .milliseconds(150)
    }

    let onClose: () -> Void
    let onTune: (Channel) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.pictureInPictureClearance) private var pictureInPictureClearance
    @State private var query = DebugLaunchOptions.searchText
    @State private var results: [SearchResult] = []
    @State private var isSearchPresented = false

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
                .columnWidth(Layout.resultsWidth, alignment: .leading)
                .padding(.vertical, DesignTokens.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: Layout.columnAlignment)
            }
            .searchField(text: $query, isPresented: $isSearchPresented)
            .screenBackground()
            .crtEffect()
            #if os(tvOS)
            .scrollClipDisabled()
            #else
            .contentMargins(.leading, DesignTokens.Spacing.md, for: .scrollContent)
            .contentMargins(.trailing, DesignTokens.Spacing.md + pictureInPictureClearance.trailing, for: .scrollContent)
            .contentMargins(.bottom, pictureInPictureClearance.bottom, for: .scrollContent)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
            #endif
        }
        #if os(tvOS)
        .onExitCommand(perform: onClose)
        #else
        // Open ready to type; cancelling the search leaves Search altogether.
        .onAppear { isSearchPresented = true }
        .onChange(of: isSearchPresented) { wasPresented, isPresented in
            if wasPresented, !isPresented { onClose() }
        }
        #endif
        .task(id: query) {
            try? await Task.sleep(for: Timing.debounce)
            guard !Task.isCancelled else { return }
            results = app.searchIndex.search(query, at: .now)
        }
    }
}

private extension View {
    /// The search field: the system placement on Apple TV; on iPhone and iPad
    /// pinned to the top (clear of the picture-in-picture window) with no
    /// autocorrection, since show titles aren't dictionary words.
    @ViewBuilder
    func searchField(text: Binding<String>, isPresented: Binding<Bool>) -> some View {
        #if os(iOS)
        searchable(text: text, isPresented: isPresented, placement: .navigationBarDrawer(displayMode: .always), prompt: "Shows and movies")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        searchable(text: text, prompt: "Shows and movies")
        #endif
    }
}
