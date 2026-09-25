import RetroGuideKit
import SwiftUI

/// Builds or edits a custom channel from any combination of filters, with a live preview.
struct ChannelEditorView: View {
    private enum Layout {
        static let sampleShowCount = 6
    }

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var draft: ChannelDefinition
    @State private var previewItems: [MediaItem] = []
    private let isNew: Bool

    init(existing: ChannelDefinition?) {
        isNew = existing == nil
        _draft = State(initialValue: existing ?? ChannelDefinition(
            id: LineupCustomization.customChannelID(),
            number: ChannelNumbering.custom.lowerBound,
            name: "",
            rule: ChannelRule(),
            ordering: .blockShuffle,
            source: .custom
        ))
    }

    var body: some View {
        SettingsPage(title: isNew ? "New Channel" : "Edit Channel") {
            SettingsSection("Name") {
                TextField("Channel name", text: $draft.name)
            }
            SettingsSection("What's on") {
                ForEach(MediaKind.allCases, id: \.self) { kind in
                    CheckmarkRow(title: kind.displayName, isSelected: draft.rule.kinds.contains(kind)) {
                        draft.rule.kinds.formSymmetricDifference([kind])
                    }
                }
                filterLink("Genres", systemImage: "theatermasks", options: facets.categories.map(FacetOption.init), selection: categorySelection)
                filterLink("Shows", systemImage: "tv", options: facets.series.map(FacetOption.init), selection: $draft.rule.seriesIDs)
                filterLink("Networks", systemImage: "antenna.radiowaves.left.and.right", options: facets.networks.map(FacetOption.init), selection: $draft.rule.networks)
                filterLink("Collections", systemImage: "square.stack", options: facets.collections.map(FacetOption.init), selection: $draft.rule.collections)
                filterLink("Decades", systemImage: "calendar", options: facets.decades.map(FacetOption.init), selection: decadeSelection)
                filterLink("Audience", systemImage: "person.2", options: audienceOptions, selection: audienceSelection)
                filterLink("Libraries", systemImage: "books.vertical", options: facets.libraries.map(FacetOption.init), selection: $draft.rule.libraryIDs)
            }
            SettingsSection("Schedule order") {
                ForEach(ScheduleOrdering.allCases, id: \.self) { ordering in
                    CheckmarkRow(title: ordering.displayName, detail: ordering.explanation, isSelected: draft.ordering == ordering) {
                        draft.ordering = ordering
                    }
                }
            }
            previewSummary
            Button(isNew ? "Create Channel" : "Save Changes", action: save)
                .buttonStyle(.retroPrimary)
                .disabled(!canSave)
        }
        .task(id: draft.rule) {
            previewItems = app.previewItems(for: draft.rule)
        }
    }

    // MARK: - Pieces

    private var facets: LibraryFacets {
        app.libraryIndex.facets
    }

    private func filterLink(
        _ title: String,
        systemImage: String,
        options: [FacetOption],
        selection: Binding<Set<String>>
    ) -> some View {
        NavigationLink {
            FacetPickerView(title: title, options: options, selection: selection)
        } label: {
            SettingsRowLabel(title: title, systemImage: systemImage, value: summary(of: selection.wrappedValue, in: options))
        }
    }

    private var previewSummary: some View {
        let runtime = previewItems.reduce(.zero) { $0 + $1.duration }
        let shows = Array(Set(previewItems.map(\.headline))).sorted().prefix(Layout.sampleShowCount)
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(previewItems.isEmpty ? "Nothing matches yet" : "\(previewItems.count) programs · \(ScheduleFormatting.hours(runtime))")
                .font(Typography.headline)
                .foregroundStyle(previewItems.isEmpty ? theme.textSecondary : theme.accent)
            if !shows.isEmpty {
                Text(shows.joined(separator: " · "))
                    .font(Typography.caption)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(2)
            }
        }
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty && !previewItems.isEmpty
    }

    private func save() {
        var definition = draft
        definition.name = draft.name.trimmingCharacters(in: .whitespaces)
        definition.callSign = CallSign.make(from: definition.name)
        if isNew {
            definition.number = app.customization.nextCustomChannelNumber
        }
        app.saveCustomChannel(definition)
        dismiss()
    }

    // MARK: - Selection adapters

    private func summary(of selection: Set<String>, in options: [FacetOption]) -> String {
        guard !selection.isEmpty else { return "Any" }
        let names = options.filter { selection.contains($0.id) }.map(\.title)
        return names.count == 1 ? names[0] : "\(names.count) selected"
    }

    private var audienceOptions: [FacetOption] {
        Audience.allCases.map { FacetOption(id: $0.rawValue, title: $0.displayName, detail: nil) }
    }

    private var audienceSelection: Binding<Set<String>> {
        Binding(
            get: { Set(draft.rule.audiences.map(\.rawValue)) },
            set: { draft.rule.audiences = Set($0.compactMap(Audience.init(rawValue:))) }
        )
    }

    /// Genres are chosen from canonical categories so every server's spellings match.
    private var categorySelection: Binding<Set<String>> {
        Binding(
            get: { Set(draft.rule.categories.map(\.rawValue)) },
            set: { draft.rule.categories = Set($0.compactMap(GenreCategory.init(rawValue:))) }
        )
    }

    private var decadeSelection: Binding<Set<String>> {
        Binding(
            get: { Set(draft.rule.decades.map(String.init)) },
            set: { draft.rule.decades = Set($0.compactMap(Int.init)) }
        )
    }
}
