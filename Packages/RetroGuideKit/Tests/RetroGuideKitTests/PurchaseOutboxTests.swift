import Foundation
import Testing
@testable import RetroGuideKit

struct PurchaseOutboxTests {
    private func path() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("queue.json")
    }

    @Test func failurePersistsAndRestoreDoesNotDuplicate() async throws {
        let file = path()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let queue = PurchaseOutbox(file: file)
        let record = PurchaseOutbox.Record(id: "one", signedTransaction: "signed")
        await queue.enqueue(record)
        await queue.enqueue(record)
        #expect(await queue.pendingCount == 1)
        let delivered = await queue.drain { _ in throw URLError(.notConnectedToInternet) }
        #expect(!delivered)
        let relaunched = PurchaseOutbox(file: file)
        #expect(await relaunched.pendingCount == 1)
        #expect(await relaunched.drain { _ in })
        #expect(await relaunched.pendingCount == 0)
    }

    @Test func updateDuringDeliveryIsNotLost() async {
        let file = path()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let queue = PurchaseOutbox(file: file)
        await queue.enqueue(.init(id: "one", signedTransaction: "old"))
        let sink = Recorder()
        await queue.drain { record in
            await sink.append(record.signedTransaction)
            if record.signedTransaction == "old" {
                await queue.enqueue(.init(id: "one", signedTransaction: "new"))
            }
        }
        #expect(await sink.values == ["old", "new"])
    }

    @Test func queueAndPayloadAreBounded() async {
        let file = path()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let queue = PurchaseOutbox(file: file)
        for index in 0..<100 { await queue.enqueue(.init(id: String(index), signedTransaction: "signed")) }
        #expect(await queue.pendingCount == PurchaseOutbox.Limits.records)
        await queue.enqueue(.init(id: "huge", signedTransaction: String(repeating: "x", count: PurchaseOutbox.Limits.transactionBytes + 1)))
        #expect(await queue.pendingCount == PurchaseOutbox.Limits.records)
    }

    @Test func unwritableStorageDoesNotThrowOrPreventDelivery() async {
        let queue = PurchaseOutbox(file: URL(fileURLWithPath: "/dev/null/queue.json"))
        await queue.enqueue(.init(id: "one", signedTransaction: "signed"))
        #expect(await queue.drain { _ in })
    }

    private actor Recorder {
        var values: [String] = []
        func append(_ value: String) { values.append(value) }
    }
}
