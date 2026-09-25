import RetroTVKit
import SwiftUI

/// Lets the user change which libraries of a server feed the channels.
struct LibrarySettingsView: View {
    let account: ServerAccount

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var libraries: [MediaLibrary]?
    @State private var errorMessage: String?

    var body: some View {
        SettingsPage(title: account.name) {
            if let libraries {
                LibraryPickerView(
                    libraries: libraries,
                    initiallySelected: account.selectedLibraryIDs,
                    confirmTitle: "Save and Rebuild Channels"
                ) { selection in
                    dismiss()
                    Task { await app.updateLibrarySelection(serverID: account.id, libraryIDs: selection) }
                }
            } else if let errorMessage {
                Text(errorMessage)
                    .font(Typography.body)
                    .foregroundStyle(theme.textSecondary)
            } else {
                ProgressView()
            }
        }
        .task {
            do {
                libraries = try await app.libraries(forServer: account.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
