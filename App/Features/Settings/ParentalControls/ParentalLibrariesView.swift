import RetroGuideKit
import SwiftUI

struct ParentalLibrariesView: View {
    @Binding var draft: ParentalPolicy
    let libraries: [FacetOption]

    var body: some View {
        SettingsPage(title: "Libraries") {
            CheckmarkRow(title: "All connected libraries", isSelected: draft.allLibraries) { draft.allLibraries = true }
            CheckmarkRow(title: "Selected libraries", isSelected: !draft.allLibraries) { draft.allLibraries = false }
            if !draft.allLibraries {
                NavigationLink {
                    FacetPickerView(title: "Choose Libraries", emptySelectionTitle: "None selected",
                        helpText: "Only these libraries can supply content. Each library lists the server it belongs to.",
                        options: libraries, selection: $draft.libraryIDs)
                } label: {
                    SettingsRowLabel(title: "Choose Libraries", systemImage: "books.vertical", value: "\(draft.libraryIDs.count) selected")
                }
                .buttonStyle(.retroRow)
            }
        }
    }
}
