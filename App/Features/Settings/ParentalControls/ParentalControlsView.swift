import RetroGuideKit
import SwiftUI

struct ParentalControlsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ParentalPolicy()
    @State private var pin = ""
    @State private var confirmation = ""
    @State private var message: String?
    @State private var choices: ParentalContentChoices?
    @State private var isSaving = false

    var body: some View {
        SettingsPage(title: String(localized: "Parental Controls")) {
            CheckmarkRow(title: String(localized: "Enable parental controls"), detail: String(localized: "Limit content and lock settings on this device."), isSelected: draft.isEnabled) {
                draft.isEnabled.toggle()
            }
            if let choices {
                if let remote = app.parentalSettingsFromCloud {
                    SettingsSection(String(localized: "Settings from iCloud")) {
                        Button("Review synced restrictions and lineup") {
                            let enabled = draft.isEnabled
                            draft = remote
                            draft.isEnabled = enabled
                        }
                        Text("Review the choices below, then Save to apply them here. Your PIN and whether parental controls are on stay unchanged.")
                            .font(Typography.settingsBody)
                    }
                }
                SettingsSection(String(localized: "Content restrictions")) {
                    NavigationLink { ParentalChannelsView(draft: $draft) } label: {
                        SettingsRowLabel(title: String(localized: "Channels"), systemImage: "list.number", value: channelSummary)
                    }
                    NavigationLink { ParentalRatingsView(draft: $draft) } label: {
                        SettingsRowLabel(title: String(localized: "Ratings"), systemImage: "checkmark.shield", value: "\(draft.maximumMovieRating.rawValue) · \(draft.maximumTVRating.rawValue)")
                    }
                    NavigationLink { ParentalLibrariesView(draft: $draft, libraries: choices.libraries) } label: {
                        SettingsRowLabel(title: String(localized: "Libraries"), systemImage: "books.vertical", value: draft.allLibraries ? ParentalValueText.all : String(localized: "\(draft.libraryIDs.count) selected"))
                    }
                    NavigationLink { ParentalAllowedContentView(draft: $draft, choices: choices) } label: {
                        SettingsRowLabel(title: String(localized: "Allowed Content"), systemImage: "checklist", value: allowedContentSummary)
                    }
                    NavigationLink {
                        ParentalTitlePicker(title: String(localized: "Blocked Shows and Movies"), catalog: choices.catalog, selections: $draft.blockedTitles, blocking: true)
                    } label: {
                        SettingsRowLabel(title: String(localized: "Blocked Shows and Movies"), systemImage: "hand.raised", value: draft.blockedTitles.isEmpty
                            ? String(localized: "None", comment: "Settings row value: no shows or movies are blocked")
                            : String(localized: "\(draft.blockedTitles.count) selected"))
                    }
                }
            }
            if !app.parentalControls.hasPIN && draft != ParentalPolicy() {
                ParentalPINSetup(pin: $pin, confirmation: $confirmation)
            }
            if let message { Text(message).font(Typography.settingsBody) }
            HStack(spacing: DesignTokens.Spacing.md) {
                Button(isSaving ? "Saving…" : "Save", action: save)
                    .buttonStyle(.retroPrimary)
                    .disabled(isSaving || choices == nil)
                    .accessibilityIdentifier("saveParentalControls")
                Button("Cancel") { dismiss() }.buttonStyle(.retro).disabled(isSaving)
            }
        }
        .task {
            guard choices == nil else { return }
            draft = app.parentalControls.policy
            let snapshots = app.servers.knownSnapshots
            let accounts = app.servers.accounts
            let loaded = await Task.detached { ParentalContentChoices(snapshots: snapshots, accounts: accounts) }.value
            guard !Task.isCancelled else { return }
            draft = draft.resolvingTitles(in: loaded.catalog)
            draft.collectionNames = Set(draft.collectionNames.map(ParentalPolicy.collectionKey))
            draft.genreNames = Set(draft.genreNames.map(ParentalPolicy.genreKey))
            choices = loaded
        }
    }

    private var channelSummary: String {
        guard draft.usesCustomLineup else { return String(localized: "Regular lineup") }
        let count = draft.channelCustomization.customChannels.count
        return count == 1 ? String(localized: "1 custom channel") : String(localized: "\(count) custom channels")
    }

    private var allowedContentSummary: String {
        if draft.selectedContentOnly { return String(localized: "Selected only") }
        if draft.allGenres { return String(localized: "All within limits") }
        return draft.genreNames.isEmpty ? String(localized: "No genres selected") : String(localized: "Genres selected")
    }

    private func save() {
        if !app.parentalControls.hasPIN {
            guard draft != ParentalPolicy() else { dismiss(); return }
            guard pin == confirmation else { message = String(localized: "The PINs do not match."); return }
        }
        isSaving = true
        Task {
            let saved = await app.applyParentalControls(draft, newPIN: app.parentalControls.hasPIN ? nil : pin)
            isSaving = false
            if saved { dismiss() } else { message = app.parentalControls.message }
        }
    }
}

private struct ParentalPINSetup: View {
    @Binding var pin: String
    @Binding var confirmation: String
    @FocusState private var focusedField: ParentalPINField.Field?
    @Environment(\.theme) private var theme

    var body: some View {
        SettingsSection(String(localized: "Create PIN")) {
            ParentalPINField(title: String(localized: "Four-digit PIN"), identifier: "newParentalPIN", pin: $pin,
                field: .create, focus: $focusedField) { focusedField = .confirm }
            ParentalPINField(title: String(localized: "Confirm PIN"), identifier: "confirmParentalPIN", pin: $confirmation,
                field: .confirm, focus: $focusedField)
            Text("Use this PIN to change settings or turn off parental controls. Keep it somewhere safe.")
                .font(Typography.settingsBody).foregroundStyle(theme.textSecondary)
        }
        .onDisappear { pin = ""; confirmation = "" }
    }
}

/// Short values shared by the parental settings rows.
enum ParentalValueText {
    static var all: String {
        String(localized: "All", comment: "Settings row value: every library or genre is allowed")
    }
}
