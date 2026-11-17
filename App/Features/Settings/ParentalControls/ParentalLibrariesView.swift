import RetroGuideKit
import SwiftUI

struct ParentalLibrariesView: View {
    @Binding var draft: ParentalPolicy
    let libraries: [FacetOption]

    var body: some View {
        SettingsPage(title: String(localized: "Libraries")) {
            CheckmarkRow(title: String(localized: "All connected libraries"), isSelected: draft.allLibraries) { draft.allLibraries = true }
            CheckmarkRow(title: String(localized: "Selected libraries"), isSelected: !draft.allLibraries) { draft.allLibraries = false }
            if !draft.allLibraries {
                NavigationLink {
                    FacetPickerView(title: String(localized: "Choose Libraries"), emptySelectionTitle: String(localized: "None selected", comment: "Nothing is chosen in this list"),
                        helpText: String(localized: "Only these libraries can supply content. Each library lists the server it belongs to."),
                        options: libraries, selection: $draft.libraryIDs)
                } label: {
                    SettingsRowLabel(title: String(localized: "Choose Libraries"), systemImage: "books.vertical", value: String(localized: "\(draft.libraryIDs.count) selected"))
                }
                .buttonStyle(.retroRow)
            }
        }
    }
}
