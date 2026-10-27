import RetroGuideKit
import SwiftUI

struct ParentalGenresView: View {
    @Binding var draft: ParentalPolicy
    let genres: [FacetOption]
    @Environment(\.theme) private var theme

    var body: some View {
        SettingsPage(title: "Allowed Genres") {
            CheckmarkRow(title: "All genres", isSelected: draft.allGenres) { draft.allGenres = true }
            CheckmarkRow(title: "Selected genres", isSelected: !draft.allGenres) { draft.allGenres = false }
            if !draft.allGenres {
                NavigationLink {
                    FacetPickerView(title: "Genres", emptySelectionTitle: "None selected. No content allowed.",
                        helpText: "A title needs at least one selected genre. Titles without a matching tag are excluded.",
                        options: availableGenres, selection: $draft.genreNames)
                } label: {
                    SettingsRowLabel(title: "Choose Genres", systemImage: "tag", value: "\(draft.genreNames.count) selected")
                }
                .buttonStyle(.retroRow)
            }
            Text("When Selected genres is enabled, each copy needs a matching server tag. Your rating, library and title restrictions also apply.")
                .font(Typography.settingsBody).foregroundStyle(theme.textSecondary)
            Text("Animation and Documentary do not necessarily mean suitable for children or educational. For a specific learning lineup, select a curated collection in Allowed Content.")
                .font(Typography.settingsBody).foregroundStyle(theme.textSecondary)
        }
    }

    private var availableGenres: [FacetOption] {
        let known = Set(genres.map(\.id))
        let unavailable = draft.genreNames.subtracting(known).sorted().map {
            FacetOption(id: $0, title: $0, detail: "Not in currently loaded libraries")
        }
        return genres + unavailable
    }
}
