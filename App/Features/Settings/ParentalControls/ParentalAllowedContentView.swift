import RetroGuideKit
import SwiftUI

struct ParentalAllowedContentView: View {
    @Binding var draft: ParentalPolicy
    let choices: ParentalContentChoices
    @Environment(\.theme) private var theme

    var body: some View {
        SettingsPage(title: "Allowed Content") {
            CheckmarkRow(title: "All shows and movies within limits", isSelected: !draft.selectedContentOnly) { draft.selectedContentOnly = false }
            CheckmarkRow(title: "Selected collections, shows and movies", isSelected: draft.selectedContentOnly) { draft.selectedContentOnly = true }
            if draft.selectedContentOnly {
                SettingsSection("Choose content") {
                    NavigationLink {
                        FacetPickerView(title: "Collections", emptySelectionTitle: "None selected",
                            helpText: "Matching copies of titles in these collections are included. Your library and rating limits still apply.",
                            options: choices.collections, selection: $draft.collectionNames)
                    } label: {
                        SettingsRowLabel(title: "Collections", systemImage: "square.stack", value: "\(draft.collectionNames.count) selected")
                    }
                    NavigationLink {
                        ParentalTitlePicker(title: "Shows and Movies", catalog: choices.catalog, selections: $draft.allowedTitles)
                    } label: {
                        SettingsRowLabel(title: "Shows and Movies", systemImage: "tv", value: "\(draft.allowedTitles.count) selected")
                    }
                }
            }
            SettingsSection("Genres") {
                NavigationLink { ParentalGenresView(draft: $draft, genres: choices.genres) } label: {
                    SettingsRowLabel(title: "Allowed Genres", systemImage: "tag", value: draft.allGenres ? "All" : "\(draft.genreNames.count) selected")
                }
            }
            Text("Your genre, library and rating limits always apply. New episodes and additions to selected collections follow the same limits.")
                .font(Typography.settingsBody).foregroundStyle(theme.textSecondary)
        }
    }
}
