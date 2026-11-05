import CloudKit
import CryptoKit
import Foundation
import RetroGuideKit

/// Stored independently of the app's local configuration so turning sync off
/// or signing out of a media server cannot delete the copy in iCloud.
struct CloudSettingsState: Codable {
    var account: String?
    var joined = false
    var replica = SettingsReplica()
    var engine: CKSyncEngine.State.Serialization?
    var refreshToken: Data?
    var systemFields: [String: Data] = [:]
    var baseline = SettingsValues()
    var backup: SettingsValues?
    var lastSync: Date?
}

enum CloudSettingsRecords {
    static let container = "iCloud.com.adamhunt.retroguide"
    static let zoneID = CKRecordZone.ID(zoneName: "ViewerSettings")
    static let recordType = "ViewerSetting"
    static let payload = "encryptedSetting"
    static let batchSize = 100

    static func id(_ key: String, zoneID: CKRecordZone.ID = zoneID) -> CKRecord.ID {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return CKRecord.ID(recordName: hash, zoneID: zoneID)
    }

    static func decode(_ record: CKRecord, zoneID: CKRecordZone.ID = zoneID) throws -> SyncedSetting {
        guard record.recordType == recordType,
              let data = record.encryptedValues[payload] as? Data,
              data.count <= SettingsReplica.Limits.recordBytes * 2 else { throw SettingsReplica.Failure.invalidRecord }
        let setting = try JSONDecoder().decode(SyncedSetting.self, from: data)
        guard id(setting.key, zoneID: zoneID) == record.recordID else { throw SettingsReplica.Failure.invalidRecord }
        return setting
    }

    static func record(_ setting: SyncedSetting, fields: Data?, zoneID: CKRecordZone.ID = zoneID) throws -> CKRecord {
        let record: CKRecord
        if let fields {
            let decoder = try NSKeyedUnarchiver(forReadingFrom: fields)
            decoder.requiresSecureCoding = true
            guard let restored = CKRecord(coder: decoder), restored.recordID == id(setting.key, zoneID: zoneID) else {
                throw SettingsReplica.Failure.invalidRecord
            }
            decoder.finishDecoding()
            record = restored
        } else {
            record = CKRecord(recordType: recordType, recordID: id(setting.key, zoneID: zoneID))
        }
        record.encryptedValues[payload] = try JSONEncoder().encode(setting) as NSData
        return record
    }

    static func fields(_ record: CKRecord) -> Data {
        let encoder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: encoder)
        encoder.finishEncoding()
        return encoder.encodedData
    }
}
