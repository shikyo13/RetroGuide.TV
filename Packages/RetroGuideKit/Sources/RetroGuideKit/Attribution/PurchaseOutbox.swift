import Foundation

/// A bounded, durable delivery queue. Delivery never controls purchase entitlement.
public actor PurchaseOutbox {
    public struct Record: Codable, Equatable, Sendable {
        public let id: String
        public let signedTransaction: String
        public init(id: String, signedTransaction: String) {
            self.id = id
            self.signedTransaction = signedTransaction
        }
    }

    public enum Limits {
        public static let records = 64
        public static let transactionBytes = 32 * 1024
        public static let fileBytes = 3 * 1024 * 1024
        public static let attempts = 4
        public static let retrySeconds: [UInt64] = [5, 30, 120]
    }

    private let file: URL
    private var records: [Record]
    private var draining = false

    public init(file: URL) {
        self.file = file
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size <= Limits.fileBytes,
           let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([Record].self, from: data) {
            records = Array(saved.filter { $0.signedTransaction.utf8.count <= Limits.transactionBytes }.suffix(Limits.records))
        } else {
            records = []
        }
    }

    public func enqueue(_ record: Record) {
        guard record.signedTransaction.utf8.count <= Limits.transactionBytes else { return }
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.append(record)
            if records.count > Limits.records { records.removeFirst(records.count - Limits.records) }
        }
        persist()
    }

    public var pendingCount: Int { records.count }

    /// Returns false on delivery failure. The failed record remains for a later retry.
    @discardableResult
    public func drain(deliver: @Sendable (Record) async throws -> Void) async -> Bool {
        guard !draining else { return true }
        draining = true
        defer { draining = false }
        while let record = records.first {
            do { try await deliver(record) } catch { return false }
            // A newer signed update may arrive while the old one is in flight.
            if let index = records.firstIndex(of: record) { records.remove(at: index) }
            persist()
        }
        return true
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            var directory = file.deletingLastPathComponent()
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            let data = try JSONEncoder().encode(records)
            #if os(iOS) || os(tvOS)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: file, options: .atomic)
            #endif
        } catch {
            // Storage failure cannot prevent buying or restoring. StoreKit can
            // supply current entitlements again on the next launch.
        }
    }
}
