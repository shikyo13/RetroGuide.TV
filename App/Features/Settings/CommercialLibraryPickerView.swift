import RetroGuideKit
import SwiftUI

struct CommercialLibraryPickerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var sources: [(account: ServerAccount, libraries: [MediaLibrary])] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    private var unavailableIDs: Set<String> {
        app.preferences.commercials.libraryIDs.subtracting(sources.flatMap { $0.libraries.map(\.id) })
    }
    var body: some View {
        SettingsPage(title: "Commercial Libraries") {
            SettingsSection("Commercial libraries") {
                Text("Use a separate library containing only commercials. Selected libraries are used only for commercials and are excluded from regular channels.")
                    .font(Typography.caption).foregroundStyle(theme.textSecondary)
                if isLoading { ProgressView() }
                ForEach(sources, id: \.account.id) { source in
                    Text("\(source.account.name) · \(source.account.kind == .plex ? "Plex" : "Jellyfin")")
                        .font(Typography.captionEmphasis).foregroundStyle(theme.accentSecondary)
                    ForEach(source.libraries) { library in
                        CheckmarkRow(title: library.title,
                                     isSelected: app.preferences.commercials.libraryIDs.contains(library.id)) {
                            var settings = app.preferences.commercials
                            if !settings.libraryIDs.insert(library.id).inserted { settings.libraryIDs.remove(library.id) }
                            if settings.libraryIDs.isEmpty { settings.isEnabled = false }
                            app.preferences.commercials = settings
                        }
                    }
                }
                if !isLoading, !unavailableIDs.isEmpty {
                    Text("Some selected libraries are unavailable. Reconnect their servers or remove these selections.")
                        .font(Typography.caption).foregroundStyle(theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Remove unavailable selections") {
                        var settings = app.preferences.commercials
                        settings.libraryIDs.subtract(unavailableIDs)
                        if settings.libraryIDs.isEmpty { settings.isEnabled = false }
                        app.preferences.commercials = settings
                    }
                }
                if let errorMessage { Text(errorMessage).font(Typography.caption).foregroundStyle(theme.textSecondary) }
            }
        }
        .task {
            sources = []
            isLoading = true
            errorMessage = nil
            for account in app.servers.accounts {
                do { sources.append((account, try await app.servers.libraries(forServer: account.id))) }
                catch { errorMessage = "Some libraries could not be loaded. Reopen this page to try again." }
            }
            isLoading = false
        }
    }
}
