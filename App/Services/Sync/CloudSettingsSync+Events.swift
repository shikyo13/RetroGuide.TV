import CloudKit
import Foundation
import RetroGuideKit

extension CloudSettingsSync: CKSyncEngineDelegate {
    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await receive(event, from: syncEngine)
    }

    nonisolated func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                             syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await prepareBatch(context, from: syncEngine)
    }

    private func prepareBatch(_ context: CKSyncEngine.SendChangesContext,
                              from sender: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard isEnabled, engine === sender, state.joined else { return nil }
        do {
            var records: [CKRecord.ID: CKRecord] = [:]
            for key in state.replica.pending.sorted() {
                guard let setting = state.replica.records[key] else { continue }
                let id = CloudSettingsRecords.id(key, zoneID: zoneID)
                guard context.options.scope.contains(.saveRecord(id)) else { continue }
                records[id] = try CloudSettingsRecords.record(setting, fields: state.systemFields[id.recordName], zoneID: zoneID)
                if records.count >= CloudSettingsRecords.batchSize { break }
            }
            guard !records.isEmpty else { return nil }
            let prepared = records
            return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: prepared.keys.map { .saveRecord($0) }) { id in
                prepared[id]
            }
        } catch { report(error); return nil }
    }

    private func receive(_ event: CKSyncEngine.Event, from sender: CKSyncEngine) {
        guard isEnabled, engine === sender else { return }
        do {
            switch event {
            case .stateUpdate(let update):
                state.engine = update.stateSerialization
                try persist()
            case .accountChange(let change):
                switch change.changeType {
                case .signIn: break
                case .signOut, .switchAccounts:
                    disable()
                    message = "The iCloud account changed. Sync is off and your settings are still on this device."
                @unknown default: disable()
                }
            case .fetchedDatabaseChanges(let fetched):
                if fetched.deletions.contains(where: { $0.zoneID == zoneID }) {
                    disable()
                    state.joined = false
                    state.engine = nil
                    state.refreshToken = nil
                    state.replica = SettingsReplica()
                    state.systemFields = [:]
                    try persist()
                    message = "The iCloud copy was removed. Your settings are still on this device. Turn sync on to set it up again."
                }
            case .fetchedRecordZoneChanges(let fetched):
                // App deletions use tombstones. Unexpected server deletions need
                // a new initial choice rather than silently rebuilding erased data.
                guard !fetched.deletions.contains(where: { $0.recordID.zoneID == zoneID }) else {
                    disable()
                    message = "The iCloud settings changed outside this app. Sync has stopped to preserve this device’s setup."
                    return
                }
                var replica = state.replica
                var fields = state.systemFields
                for change in fetched.modifications where change.record.recordID.zoneID == zoneID {
                    let record = change.record
                    let value = try CloudSettingsRecords.decode(record, zoneID: zoneID)
                    try replica.merge(value)
                    fields[record.recordID.recordName] = CloudSettingsRecords.fields(record)
                }
                state.replica = replica
                state.systemFields = fields
                try persist()
                settingsRevision += 1
            case .sentRecordZoneChanges(let sent):
                for record in sent.savedRecords {
                    let setting = try CloudSettingsRecords.decode(record, zoneID: zoneID)
                    state.replica.acknowledge(setting)
                    state.systemFields[record.recordID.recordName] = CloudSettingsRecords.fields(record)
                }
                for failed in sent.failedRecordSaves {
                    if failed.error.code == .serverRecordChanged, let record = failed.error.serverRecord {
                        let setting = try CloudSettingsRecords.decode(record, zoneID: zoneID)
                        try state.replica.merge(setting)
                        state.systemFields[record.recordID.recordName] = CloudSettingsRecords.fields(record)
                        // The local value may still be the winner. Re-submit it
                        // with the server's change tag, not a blind overwrite.
                        if state.replica.records[setting.key] != setting { state.replica.retry(setting.key) }
                    } else {
                        report(failed.error)
                    }
                }
                try persist()
                settingsRevision += 1
                enqueue()
                applyLatest()
            case .didFetchChanges:
                if state.joined {
                    applyLatest()
                    if message == nil, !hasPendingApplication, state.replica.pending.isEmpty {
                        state.lastSync = .now
                        lastSync = state.lastSync
                        try persist()
                    }
                }
            case .didSendChanges:
                if state.joined, state.replica.pending.isEmpty {
                    state.lastSync = .now
                    lastSync = state.lastSync
                    if !hasPendingApplication { message = nil }
                    try persist()
                }
            case .sentDatabaseChanges(let sent):
                if let failure = sent.failedZoneSaves.first { report(failure.error) }
            default: break
            }
        } catch {
            // Stop before advancing past an unreadable record. The next explicit
            // retry fetches again using the last persisted engine state.
            disable()
            report(error)
        }
    }
}
