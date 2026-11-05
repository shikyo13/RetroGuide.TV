import CloudKit
import Foundation
import RetroGuideKit

extension CloudSettingsSync {
    /// A foreground refresh reads the zone directly so a delayed push cannot
    /// make an explicit refresh rely on the engine's cached change knowledge.
    /// Its separate cursor fetches only changes since the previous refresh.
    func refreshFromServer(_ database: CKDatabase, using active: CKSyncEngine) async throws {
        var resetExpiredToken = false
        while isEnabled, engine === active {
            try Task.checkCancellation()
            do {
                let token = try state.refreshToken.map {
                    try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0)
                } ?? nil
                let page = try await database.recordZoneChanges(inZoneWith: zoneID, since: token,
                    resultsLimit: CloudSettingsRecords.batchSize)
                guard isEnabled, engine === active else { return }
                try Task.checkCancellation()
                guard page.deletions.isEmpty else {
                    disable()
                    message = "The iCloud settings changed outside this app. Sync has stopped to preserve this device’s setup."
                    return
                }
                let records = try page.modificationResultsByID.values.map { try $0.get().record }
                let cursor = try NSKeyedArchiver.archivedData(withRootObject: page.changeToken, requiringSecureCoding: true)
                try mergeRefreshPage(records, cursor: cursor)
                if !page.moreComing { return }
            } catch let error as CKError where error.code == .changeTokenExpired && !resetExpiredToken {
                resetExpiredToken = true
                state.refreshToken = nil
                try persist()
            } catch let error as CKError where error.code == .zoneNotFound && !state.joined {
                return
            }
        }
    }

    /// A malformed record cannot advance the cursor past an unapplied page.
    func mergeRefreshPage(_ records: [CKRecord], cursor: Data) throws {
        var replica = state.replica
        var fields = state.systemFields
        for record in records {
            let setting = try CloudSettingsRecords.decode(record, zoneID: zoneID)
            try replica.merge(setting)
            fields[record.recordID.recordName] = CloudSettingsRecords.fields(record)
        }
        state.replica = replica
        state.systemFields = fields
        state.refreshToken = cursor
        try persist()
        settingsRevision += 1
    }
}
