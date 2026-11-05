import Foundation
import RetroGuideKit

extension AppModel {
    func configureSettingsSync() {
        settingsSync.readLocal = { [weak self] in
            guard let self else { return SettingsValues() }
            return try sharedSettings().encoded()
        }
        settingsSync.apply = { [weak self] values in
            guard let self else { return false }
            return try applySharedSettings(values)
        }
        reminders.onUserChange = { [weak self] reminder, adding in
            guard let self else { return }
            var shared = store.sharedReminders ?? reminders.pending
            shared.removeAll { $0.id == reminder.id || $0.start < .now }
            if adding { shared.append(reminder) }
            store.sharedReminders = shared
            recordSettingsChange()
        }
    }

    func recordSettingsChange() {
        guard !isApplyingSyncedSettings else { return }
        settingsSync.captureLocalChanges()
    }

    static func sharedServerKey(_ account: ServerAccount) -> String {
        [account.kind.rawValue, account.id, account.userID ?? ""].joined(separator: ":")
    }

    func seedSharedSelections() {
        var shared = store.sharedLibraries
        for account in servers.accounts {
            let key = Self.sharedServerKey(account)
            if let saved = shared[key] {
                servers.setSelectedLibraries(saved, serverID: account.id)
            } else { shared[key] = account.selectedLibraryIDs }
        }
        store.sharedLibraries = shared
        if store.sharedReminders == nil { store.sharedReminders = reminders.pending }
    }

    func sharedSettings() -> SharedSettings {
        var shared = SharedSettings()
        shared.themeID = preferences.themeID.rawValue
        shared.showsScanlines = preferences.showsScanlines
        shared.scheduleGrid = preferences.scheduleGrid
        shared.commercials = preferences.commercials
        shared.lineup = regularCustomization
        shared.favoriteIDs = viewing.favoriteIDs
        shared.audioRules = store.trackRules.audioChoices
        shared.subtitleRules = store.trackRules.subtitleChoices
        shared.subtitleOffsets = store.showSubtitleOffsets.choices
        shared.libraries = store.sharedLibraries
        shared.reminders = store.sharedReminders ?? reminders.pending
        if parentalControls.hasPIN { shared.parentalPolicy = parentalControls.policy }
        return shared
    }

    /// Importing never changes a PIN, authorization state or parental policy.
    /// The latter is reviewed and saved through the existing protected screen.
    var parentalSettingsFromCloud: ParentalPolicy? {
        guard settingsSync.isEnabled,
              let remote = try? SharedSettings(values: settingsSync.values).parentalPolicy else { return nil }
        var local = parentalControls.policy
        local.isEnabled = false
        return remote == local ? nil : remote
    }

    func applySharedSettings(_ values: SettingsValues) throws -> Bool {
        guard !parentalControls.needsAuthorization, !isApplyingParentalControls,
              !isManagingStartup, !isRefreshing, phase == .ready || phase == .onboarding else { return false }
        let shared = try SharedSettings(values: values)
        // Decode every field before modifying any local setting.
        let nextTheme = shared.themeID.flatMap(ThemeID.init(rawValue:)) ?? preferences.themeID
        let oldPreferences = preferences
        let oldLineup = regularCustomization
        var proposedPreferences = preferences
        proposedPreferences.themeID = nextTheme
        proposedPreferences.showsScanlines = shared.showsScanlines
        proposedPreferences.scheduleGrid = shared.scheduleGrid
        proposedPreferences.commercials = shared.commercials
        var proposedViewing = viewing
        proposedViewing.favoriteIDs = shared.favoriteIDs
        let rules = TrackRules(audio: shared.audioRules, subtitles: shared.subtitleRules)
        var offsets = ShowSubtitleOffsets()
        for (show, offset) in shared.subtitleOffsets.sorted(by: { $0.key < $1.key }) { offsets.set(offset, for: show) }
        try store.validateSyncImport(preferences: proposedPreferences, viewing: proposedViewing,
            customization: shared.lineup, rules: rules, offsets: offsets, libraries: shared.libraries, reminders: shared.reminders)
        var librariesChanged = false
        isApplyingSyncedSettings = true
        defer { isApplyingSyncedSettings = false }
        preferences = proposedPreferences
        if oldPreferences.commercials != preferences.commercials { tuner.enforcePlaybackAccess() }
        regularCustomization = shared.lineup
        store.customization = shared.lineup
        viewing = proposedViewing
        if rules != store.trackRules {
            store.trackRules = rules
            tuner.replaceTrackRules(rules)
            trackSync.setCurrent(rules: rules, preferences: store.languagePreferences)
        }
        store.showSubtitleOffsets = offsets
        tuner.restoreShowSubtitleOffsets(offsets)
        store.sharedLibraries = shared.libraries
        store.sharedReminders = shared.reminders
        for account in servers.accounts {
            guard let selected = shared.libraries[Self.sharedServerKey(account)],
                  selected != account.selectedLibraryIDs else { continue }
            servers.setSelectedLibraries(selected, serverID: account.id)
            librariesChanged = true
        }
        applyHomeScreenTheme()
        let gridChanged = oldPreferences.scheduleGrid != preferences.scheduleGrid
        let rebuild = gridChanged || oldPreferences.commercials != preferences.commercials || oldLineup != regularCustomization
        if librariesChanged || rebuild {
            let reloadLibraries = librariesChanged
            syncedSettingsRefresh?.cancel()
            syncedSettingsRefresh = Task { [weak self] in
                guard let self, !Task.isCancelled else { return }
                if reloadLibraries { await refreshLibrary() }
                else { await rebuildIndexAndLineup() }
                guard !Task.isCancelled else { return }
                // A different grid moves program start times; rejoin live as a local change does.
                if gridChanged, !tuner.isWatchingFromBeginning, let channel = tuner.channel {
                    tuner.tune(to: channel, isAutomatic: true)
                }
                refreshSyncedReminders()
            }
        } else { refreshSyncedReminders() }
        return true
    }

    func refreshSyncedReminders() {
        guard settingsSync.hasMigratedTrackRules, pro.hasLoaded, let shared = store.sharedReminders else { return }
        let eligible = pro.isPro ? shared.filter { reminder in
            guard reminder.start > .now,
                  let channel = visibleChannels.first(where: { $0.isIdentified(by: reminder.channelID) }),
                  let program = channel.timeline.program(at: reminder.start) else { return false }
            return program.item.id == reminder.itemID && program.start == reminder.start
        } : []
        reminders.replaceFromSync(eligible)
    }
}
