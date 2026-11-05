import Foundation

/// One independently editable setting. A nil value is a retained deletion.
public struct SyncedSetting: Codable, Equatable, Sendable {
    public let schema: Int
    public let key: String
    public let revision: SettingsRevision
    public let value: Data?

    public init(key: String, revision: SettingsRevision, value: Data?) {
        schema = SettingsReplica.schema
        self.key = key
        self.revision = revision
        self.value = value
    }
}

/// A logical clock avoids relying on different devices having matching clocks.
public struct SettingsRevision: Codable, Equatable, Comparable, Sendable {
    public let counter: UInt64
    public let device: String

    public init(counter: UInt64, device: String) {
        self.counter = counter
        self.device = device
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.counter == rhs.counter ? lhs.device < rhs.device : lhs.counter < rhs.counter
    }
}

/// Per-setting conflict resolution with durable tombstones. Removing a favorite
/// must not resurrect it when an offline device reconnects.
public struct SettingsReplica: Codable, Sendable {
    public static let schema = 1
    public enum Limits {
        public static let recordBytes = 192 * 1_024
        public static let records = 12_000
        public static let totalBytes = 8 * 1_024 * 1_024
        public static let keyBytes = 4_096
    }
    public enum Failure: Error { case unsupportedSchema, invalidRecord, capacityReached, deviceStorageLimit }
    public private(set) var records: [String: SyncedSetting] = [:]
    public private(set) var pending: Set<String> = []
    public private(set) var clock: UInt64 = 0
    public private(set) var device: String

    public init(device: String = UUID().uuidString) { self.device = device }

    /// A restored device backup must not create revisions using another
    /// installation's writer identity. Existing queued revisions remain valid.
    public mutating func startNewSession() { device = UUID().uuidString }

    public var values: SettingsValues {
        SettingsValues(records.compactMapValues(\.value))
    }

    /// Only actual local edits are written. Remote settings which cannot yet be
    /// applied locally (for example a disconnected library) remain untouched.
    public mutating func capture(_ next: SettingsValues, comparedTo previous: SettingsValues) throws {
        var draft = self
        for key in Set(previous.entries.keys).union(next.entries.keys).sorted()
        where previous.entries[key] != next.entries[key] {
            guard draft.clock < UInt64.max - 2 else { throw Failure.invalidRecord }
            draft.clock += 1
            let record = SyncedSetting(key: key, revision: .init(counter: draft.clock, device: device), value: next.entries[key])
            try Self.validate(record)
            draft.records[key] = record
            draft.pending.insert(key)
        }
        try draft.validateCapacity()
        self = draft
    }

    public mutating func merge(_ incoming: SyncedSetting) throws {
        try Self.validate(incoming)
        var draft = self
        draft.clock = max(clock, incoming.revision.counter)
        if let local = records[incoming.key], local.revision >= incoming.revision {
            guard local.revision != incoming.revision || local == incoming else { throw Failure.invalidRecord }
            return
        }
        draft.records[incoming.key] = incoming
        draft.pending.remove(incoming.key)
        try draft.validateCapacity()
        self = draft
    }

    /// Acknowledging an older upload cannot clear a newer edit to the same key.
    public mutating func acknowledge(_ sent: SyncedSetting) {
        if records[sent.key] == sent { pending.remove(sent.key) }
    }

    public mutating func retry(_ key: String) { if records[key] != nil { pending.insert(key) } }

    private static func validate(_ record: SyncedSetting) throws {
        guard record.schema == schema else { throw Failure.unsupportedSchema }
        guard !record.key.isEmpty, record.key.utf8.count <= Limits.keyBytes,
              record.revision.counter > 0, record.revision.counter < UInt64.max - 1,
              UUID(uuidString: record.revision.device) != nil,
              (record.value?.count ?? 0) <= Limits.recordBytes else { throw Failure.invalidRecord }
    }

    private func validateCapacity() throws {
        guard records.count <= Limits.records,
              records.values.reduce(0, { $0 + ($1.value?.count ?? 0) + $1.key.utf8.count }) <= Limits.totalBytes
        else { throw Failure.capacityReached }
    }
}

/// Encoded configuration only. Media catalogs and credentials have no entry point.
public struct SettingsValues: Codable, Equatable, Sendable {
    public var entries: [String: Data]
    public init(_ entries: [String: Data] = [:]) { self.entries = entries }

    public mutating func put<T: Encodable>(_ value: T, _ key: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        entries[key] = try encoder.encode(value)
    }

    public func get<T: Decodable>(_ type: T.Type, _ key: String) throws -> T? {
        try entries[key].map { try JSONDecoder().decode(type, from: $0) }
    }

    /// Set-backed payloads need a stable representation across process launches.
    /// Use only for values whose collection order has no meaning.
    mutating func putUnordered<T: Encodable>(_ value: T, _ key: String) throws {
        let data = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        func normalized(_ object: Any) throws -> Any {
            if let dictionary = object as? [String: Any] { return try dictionary.mapValues(normalized) }
            if let array = object as? [Any] {
                let values = try array.map(normalized)
                return try values.map { value in
                    (value, try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]))
                }.sorted { $0.1.lexicographicallyPrecedes($1.1) }.map(\.0)
            }
            return object
        }
        entries[key] = try JSONSerialization.data(withJSONObject: normalized(object), options: [.sortedKeys, .fragmentsAllowed])
    }

    public static func key(_ group: String, _ id: String) -> String {
        group + "/" + Data(id.utf8).base64EncodedString()
    }

    public func members<T: Decodable>(_ type: T.Type, _ group: String) throws -> [String: T] {
        var values: [String: T] = [:]
        for (key, data) in entries where key.hasPrefix(group + "/") {
            guard let bytes = Data(base64Encoded: String(key.dropFirst(group.count + 1))),
                  let id = String(data: bytes, encoding: .utf8) else { throw SettingsReplica.Failure.invalidRecord }
            values[id] = try JSONDecoder().decode(type, from: data)
        }
        return values
    }
}
