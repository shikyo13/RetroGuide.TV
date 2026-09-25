import RetroGuideKit
import SwiftUI

/// Multi-select list of libraries. Used in onboarding and in Settings.
struct LibraryPickerView: View {
    private enum Layout {
        static let listWidth = PlatformMetric.value(tv: CGFloat(1_000), touch: 600)
    }

    let libraries: [MediaLibrary]
    let confirmTitle: String
    let onConfirm: (Set<String>) -> Void

    @State private var selection: Set<String>
    @Environment(\.theme) private var theme

    init(libraries: [MediaLibrary], initiallySelected: Set<String>? = nil, confirmTitle: String, onConfirm: @escaping (Set<String>) -> Void) {
        self.libraries = libraries
        self.confirmTitle = confirmTitle
        self.onConfirm = onConfirm
        let defaultSelection = initiallySelected.flatMap { $0.isEmpty ? nil : $0 } ?? Set(libraries.map(\.id))
        _selection = State(initialValue: defaultSelection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text("Which libraries should be on TV?")
                .font(Typography.title)
                .foregroundStyle(theme.textPrimary)
            VStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(libraries) { library in
                    Button {
                        toggle(library.id)
                    } label: {
                        HStack(spacing: DesignTokens.Spacing.md) {
                            Image(systemName: selection.contains(library.id) ? "checkmark.circle.fill" : "circle")
                            Image(systemName: library.kind == .movies ? "film" : "tv")
                            Text(library.title)
                            Spacer()
                            Text(library.kind == .movies ? "Movies" : "TV Shows")
                                .secondaryText()
                        }
                    }
                    .buttonStyle(.retroRow)
                }
            }
            Button(confirmTitle) {
                onConfirm(selection)
            }
            .buttonStyle(.retroPrimary)
            .disabled(selection.isEmpty)
        }
        .columnWidth(Layout.listWidth)
    }

    private func toggle(_ id: String) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }
}
