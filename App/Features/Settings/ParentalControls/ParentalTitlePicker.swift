import RetroGuideKit
import SwiftUI

struct ParentalTitlePicker: View {
    let title: String
    let catalog: ParentalTitleCatalog
    @Binding var selections: [ParentalTitleIdentity]
    var blocking = false

    private var unavailable: [ParentalTitleIdentity] {
        selections.filter { catalog.selectedIDs(for: [$0], blocking: blocking).isEmpty }
    }

    var body: some View {
        let unavailable = unavailable
        let options = catalog.titles.map { title in
            FacetOption(id: title.id, title: title.name, detail: detail(title.identity, servers: title.serverNames))
        } + unavailable.map { identity in
            FacetOption(id: savedID(identity), title: identity.name, detail: "Currently unavailable")
        }
        FacetPickerView(title: title, emptySelectionTitle: "None selected", helpText: blocking
            ? "Blocked shows and movies are hidden from every channel, including matching copies on other servers."
            : "Selecting a show includes its episodes. Matching copies on other servers are included, within your library and rating limits.",
            options: options, selection: Binding(get: {
                catalog.selectedIDs(for: selections, blocking: blocking).union(unavailable.map(savedID))
            }, set: { ids in
                selections = catalog.identities(for: ids) + unavailable.filter { ids.contains(savedID($0)) }
            }))
    }

    private func detail(_ identity: ParentalTitleIdentity, servers: [String]) -> String {
        ([identity.kind == .movie ? "Movie" : "TV show"] + (identity.year.map { [String($0)] } ?? []) + servers).joined(separator: " · ")
    }

    private func savedID(_ identity: ParentalTitleIdentity) -> String { "saved/" + (identity.sourceIDs.sorted().first ?? identity.name) }
}
