import RetroGuideKit
import SwiftUI

struct ParentalAllowedContentView: View {
    @Binding var draft: ParentalPolicy
    let choices: ParentalContentChoices
    @Environment(\.theme) private var theme

    var body: some View {
        SettingsPage(title: String(localized: "Allowed Content")) {
            CheckmarkRow(title: String(localized: "All shows and movies within limits"), isSelected: !draft.selectedContentOnly) { draft.selectedContentOnly = false }
            CheckmarkRow(title: String(localized: "Selected collections, shows and movies"), isSelected: draft.selectedContentOnly) { draft.selectedContentOnly = true }
            if draft.selectedContentOnly {
                SettingsSection(String(localized: "Choose content")) {
                    NavigationLink {
                        FacetPickerView(title: String(localized: "Collections"), emptySelectionTitle: String(localized: "None selected", comment: "Nothing is chosen in this list"),
                            helpText: String(localized: "Matching copies of titles in these collections are included. Your library and rating limits still apply."),
                            options: choices.collections, selection: $draft.collectionNames)
                    } label: {
                        SettingsRowLabel(title: String(localized: "Collections"), systemImage: "square.stack", value: String(localized: "\(draft.collectionNames.count) selected"))
                    }
                    NavigationLink {
                        ParentalTitlePicker(title: String(localized: "Shows and Movies"), catalog: choices.catalog, selections: $draft.allowedTitles)
                    } label: {
                        SettingsRowLabel(title: String(localized: "Shows and Movies"), systemImage: "tv", value: String(localized: "\(draft.allowedTitles.count) selected"))
                    }
                }
            }
            SettingsSection(String(localized: "Genres")) {
                NavigationLink { ParentalGenresView(draft: $draft, genres: choices.genres) } label: {
                    SettingsRowLabel(title: String(localized: "Allowed Genres"), systemImage: "tag", value: draft.allGenres ? ParentalValueText.all : String(localized: "\(draft.genreNames.count) selected"))
                }
            }
            Text("Your genre, library and rating limits always apply. New episodes and additions to selected collections follow the same limits.")
                .font(Typography.settingsBody).foregroundStyle(theme.textSecondary)
        }
    }
}
