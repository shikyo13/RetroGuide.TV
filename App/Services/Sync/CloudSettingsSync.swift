import CloudKit
import Foundation
import Observation
import OSLog
import RetroGuideKit

/// Keeps a durable local journal; networking never participates in local saves.
@MainActor @Observable
final class CloudSettingsSync {
    private enum Storage {
        static let enabled = "cloudSettings.enabled.v1"
        static let migrated = "cloudSettings.migratedTrackRules.v1"
        static let account = "cloudSettings.account.v1"
    }
    private(set) var isEnabled: Bool
    private(set) var isBusy = false
    private(set) var needsInitialChoice = false
    private(set) var hasPendingApplication = false
    var message: String?
    var lastSync: Date?
    var settingsRevision = 0
    var summary: String {
        _ = settingsRevision
        if !isEnabled { return "Off" }
        if needsInitialChoice { return "Choose setup" }
        if hasPendingApplication { return "Changes waiting" }
        if message != nil { return "Needs attention" }
        if isBusy { return "Syncing…" }
        return state.replica.pending.isEmpty ? "On" : "Waiting to sync"
    }
    var hasBackup: Bool { _ = settingsRevision; return state.backup != nil }
    var hasMigratedTrackRules: Bool { defaults.bool(forKey: Storage.migrated) }
    var values: SettingsValues { _ = settingsRevision; return state.replica.values }

    @ObservationIgnored var readLocal: (() throws -> SettingsValues)?
    @ObservationIgnored var apply: ((SettingsValues) throws -> Bool)?
    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored let storage: CloudSettingsStorage
    @ObservationIgnored var state: CloudSettingsState
    @ObservationIgnored var engine: CKSyncEngine?
    @ObservationIgnored let zoneID: CKRecordZone.ID
    @ObservationIgnored private let automaticallySync: Bool
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var corruptState = false

    init(defaults: UserDefaults = .standard, storage: CloudSettingsStorage = CloudSettingsStorage(), zoneID: CKRecordZone.ID = CloudSettingsRecords.zoneID, automaticallySync: Bool = true) {
        self.defaults = defaults
        self.storage = storage
        self.zoneID = zoneID
        self.automaticallySync = automaticallySync
        isEnabled = defaults.bool(forKey: Storage.enabled)
        do {
            state = try storage.load() ?? CloudSettingsState()
            state.replica.startNewSession()
            // This small binding survives a tvOS cache purge. It prevents local
            // settings being published into a different iCloud account.
            if state.account == nil { state.account = defaults.string(forKey: Storage.account) }
        }
        catch {
            state = CloudSettingsState()
            corruptState = true
            isEnabled = false
            message = "The saved sync journal could not be read. Your settings on this device are unchanged."
        }
        lastSync = state.lastSync
    }

    func startIfEnabled() {
        guard isEnabled, engine == nil, task == nil else { return }
        retry()
    }

    func finishTrackRulesMigration() { defaults.set(true, forKey: Storage.migrated) }

    func enable() {
        if corruptState {
            do {
                try storage.preserveUnreadableJournal()
                state = CloudSettingsState()
                state.account = defaults.string(forKey: Storage.account)
                corruptState = false
            } catch { report(error); return }
        }
        isEnabled = true
        defaults.set(true, forKey: Storage.enabled)
        retry()
    }

    func disable() {
        generation += 1
        isEnabled = false
        defaults.set(false, forKey: Storage.enabled)
        task?.cancel()
        task = nil
        let old = engine
        engine = nil
        if let old { Task { await old.cancelOperations() } }
        isBusy = false
        needsInitialChoice = false
        hasPendingApplication = false
    }

    func disconnectLocalSetup() {
        disable()
        do {
            try storage.save(state, name: "previous-setup")
            state = CloudSettingsState()
            try persist()
        } catch { report(error) }
    }

    func retry() {
        guard isEnabled, task == nil, !corruptState else { return }
        let generation = generation
        task = Task { [weak self] in
            guard let self else { return }
            isBusy = true
            message = nil
            defer {
                if generation == self.generation { isBusy = false; task = nil }
            }
            do {
                let container = CKContainer(identifier: CloudSettingsRecords.container)
                guard try await container.accountStatus() == .available else {
                    message = "Sign in to iCloud in this device’s Settings, then try again."
                    return
                }
                let account = try await container.userRecordID().recordName
                guard isEnabled, generation == self.generation, !Task.isCancelled else { return }
                guard try acceptAccount(account) else { return }
                try persist()
                if engine == nil { makeEngine(container) }
                guard let active = engine else { return }
                if state.joined { captureLocalChanges() }
                try await active.fetchChanges()
                guard isEnabled, engine === active, generation == self.generation else { return }
                try await refreshFromServer(container.privateCloudDatabase, using: active)
                guard isEnabled, engine === active, generation == self.generation else { return }
                if !state.joined {
                    if state.replica.records.isEmpty { try finishJoining(useLocal: true) }
                    else { needsInitialChoice = true }
                } else {
                    applyLatest()
                    enqueue()
                    try await active.sendChanges()
                }
            } catch { if generation == self.generation { report(error) } }
        }
    }

    func acceptAccount(_ account: String) throws -> Bool {
        if let previous = state.account, previous != account {
            disable()
            message = "The iCloud account changed. Sync is off and this device’s settings are unchanged. Turn it on to choose a setup for the new account."
            // Keep the old journal as a local recovery copy, never enqueue it
            // against the new account.
            try storage.save(state, name: "previous-account")
            state = CloudSettingsState()
            defaults.removeObject(forKey: Storage.account)
            try persist()
            return false
        }
        state.account = account
        defaults.set(account, forKey: Storage.account)
        return true
    }

    /// Both choices save a local recovery copy first. No writes happen until
    /// the initial cloud fetch completed successfully.
    func chooseInitialSetup(useLocal: Bool) {
        guard needsInitialChoice, isEnabled else { return }
        do { try finishJoining(useLocal: useLocal) }
        catch { report(error) }
    }

    private func finishJoining(useLocal: Bool) throws {
        guard let local = try readLocal?() else { return }
        state.backup = local
        state.baseline = local
        if useLocal { try state.replica.capture(local, comparedTo: state.replica.values) }
        state.joined = true
        try persist()
        settingsRevision += 1
        finishTrackRulesMigration()
        needsInitialChoice = false
        if !useLocal { applyLatest() }
        enqueue()
    }

    func captureLocalChanges() {
        guard isEnabled, state.joined, !corruptState, let readLocal else { return }
        do {
            let current = try readLocal()
            try state.replica.capture(current, comparedTo: state.baseline)
            state.baseline = current
            try persist()
            settingsRevision += 1
            enqueue()
        } catch { report(error) }
    }

    func applyLatest() {
        guard isEnabled, state.joined, let apply else { return }
        do {
            hasPendingApplication = try !apply(state.replica.values)
            if !hasPendingApplication, let current = try readLocal?() {
                state.baseline = current
                try persist()
            }
        } catch { hasPendingApplication = true; report(error) }
    }

    func restoreBackup() {
        guard let backup = state.backup, let apply else { return }
        do {
            guard try apply(backup) else { return }
            captureLocalChanges()
        } catch { report(error) }
    }

    func makeEngine(_ container: CKContainer) {
        var configuration = CKSyncEngine.Configuration(database: container.privateCloudDatabase,
            stateSerialization: state.engine, delegate: self)
        // Before joining, only reads are allowed: enqueue and prepareBatch
        // both require a completed initial choice.
        configuration.automaticallySync = automaticallySync
        engine = CKSyncEngine(configuration)
        if state.joined { enqueue() }
    }

    func enqueue() {
        guard isEnabled, state.joined, let engine else { return }
        let wanted = Set(state.replica.pending.map { CloudSettingsRecords.id($0, zoneID: zoneID) })
        let obsolete = engine.state.pendingRecordZoneChanges.filter { change in
            if case .saveRecord(let id) = change { return !wanted.contains(id) }
            return true
        }
        engine.state.remove(pendingRecordZoneChanges: obsolete)
        guard !wanted.isEmpty else { return }
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        engine.state.add(pendingRecordZoneChanges: state.replica.pending.sorted().map { .saveRecord(CloudSettingsRecords.id($0, zoneID: zoneID)) })
    }

    func persist() throws {
        do { try storage.save(state) }
        catch { disable(); throw error }
    }

    func report(_ error: Error) {
        let failure = error as NSError
        Logger(subsystem: "com.adamhunt.retroguide", category: "SettingsSync")
            .error("Sync failed: \(failure.domain, privacy: .public) \(failure.code, privacy: .public)")
        if case SettingsReplica.Failure.deviceStorageLimit = error {
            message = "This setup is too large for this Apple TV’s settings storage. Your current setup has been kept."
            return
        }
        switch (error as? CKError)?.code {
        case .notAuthenticated, .accountTemporarilyUnavailable:
            message = "iCloud is unavailable. Your changes are saved on this device."
        case .quotaExceeded:
            message = "Your iCloud storage is full. Free some space, then try again."
        case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            message = "Waiting for iCloud. Your changes are saved on this device and will retry automatically."
        default:
            if error is CocoaError || error is CloudSettingsStorage.Failure {
                message = "Sync could not save its local data. Free some device storage, then turn sync on again. Your app settings are unchanged."
            } else if error is SettingsReplica.Failure {
                message = "These settings could not be synced safely. Update RetroGuide.TV on your other devices, then try again. Your local setup is unchanged."
            } else {
                message = "iCloud Sync could not finish. Your changes are saved on this device. Try again later."
            }
        }
    }
}
