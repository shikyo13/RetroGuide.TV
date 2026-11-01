import RetroGuideKit
import SwiftUI

struct CommercialBreaksView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    var body: some View {
        SettingsPage(title: "Commercial Breaks") {
            Text("Play clips from a separate commercial library between programs. Shows and movies play without interruptions.")
                .font(Typography.body).foregroundStyle(theme.textSecondary)
            CheckmarkRow(title: "Enable commercial breaks", isSelected: app.preferences.commercials.isEnabled) {
                app.preferences.commercials.isEnabled.toggle()
            }.disabled(app.preferences.commercials.libraryIDs.isEmpty)
            NavigationLink { CommercialLibraryPickerView() } label: {
                SettingsRowLabel(title: "Commercial libraries", systemImage: "folder",
                    value: app.preferences.commercials.libraryIDs.isEmpty ? "Choose libraries" : "\(app.preferences.commercials.libraryIDs.count) selected")
            }
            if app.preferences.commercials.libraryIDs.isEmpty {
                Text("Choose a library containing only commercials to enable breaks.")
                    .font(Typography.caption).foregroundStyle(theme.textSecondary)
            }
            SettingsSection("Between programs") {
                ForEach(CommercialBreakSettings.Count.allCases, id: \.self) { count in
                    CheckmarkRow(title: count.displayName, isSelected: app.preferences.commercials.count == count) {
                        app.preferences.commercials.count = count
                    }
                }
                Text("Breaks use the combined running time of the selected clips, which is included in the guide. If fewer clips are available, each plays once. Program start-time alignment may add an intermission before the next program.")
                    .font(Typography.caption).foregroundStyle(theme.textSecondary)
            }
            Text("Parental Controls also apply to commercials. Unrated clips are excluded when unrated content is blocked.")
                .font(Typography.caption).foregroundStyle(theme.textSecondary)
            Button("Refresh commercials") { Task { await app.refreshCommercials(force: true) } }
                .disabled(app.commercialLibrary.isLoading)
            if app.commercialLibrary.isLoading { ProgressView("Loading commercials…") }
            else if app.preferences.commercials.isEnabled {
                Text(app.commercialLibrary.items.isEmpty ? "No commercials available. Check your libraries and Parental Controls." : "\(app.commercialLibrary.items.count) commercials available")
                    .font(Typography.caption).foregroundStyle(theme.textSecondary)
            }
            if let error = app.commercialLibrary.errorMessage { Text(error).font(Typography.caption).foregroundStyle(theme.textSecondary) }
        }
    }
}
