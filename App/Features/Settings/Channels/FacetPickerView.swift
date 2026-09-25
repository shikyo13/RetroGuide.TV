import RetroGuideKit
import SwiftUI

/// One choice in a ``FacetPickerView``.
struct FacetOption: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String?
}

extension FacetOption {
    @MainActor
    init(_ facet: FacetValue) {
        self.init(id: facet.id, title: facet.name, detail: "\(facet.itemCount) · \(ScheduleFormatting.hours(facet.runtime))")
    }
}

/// Searchable multi-select list used by the channel editor.
struct FacetPickerView: View {
    private enum Layout {
        /// Lists longer than this get a search field.
        static let searchThreshold = 15
    }

    let title: String
    let options: [FacetOption]
    @Binding var selection: Set<String>

    @State private var query = ""
    @Environment(\.theme) private var theme

    var body: some View {
        SettingsPage(title: title) {
            HStack(spacing: DesignTokens.Spacing.md) {
                Text(selection.isEmpty ? "Any" : "\(selection.count) selected")
                    .font(Typography.callout)
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                if !selection.isEmpty {
                    Button("Clear") { selection.removeAll() }
                        .buttonStyle(.retro)
                }
            }
            if options.count > Layout.searchThreshold {
                TextField("Search \(title.lowercased())", text: $query)
            }
            LazyVStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(filteredOptions) { option in
                    CheckmarkRow(title: option.title, detail: option.detail, isSelected: selection.contains(option.id)) {
                        toggle(option.id)
                    }
                }
            }
        }
    }

    private var filteredOptions: [FacetOption] {
        guard !query.isEmpty else { return options }
        return options.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private func toggle(_ id: String) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }
}
