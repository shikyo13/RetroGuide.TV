import Foundation
import Testing
@testable import RetroGuideKit

@Suite("Usage ledger")
struct UsageLedgerTests {
    private func file() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("usage.json")
    }

    @Test("A batch the service refuses is dropped; one it can't reach is kept")
    func refusedAndOffline() async {
        let ledger = UsageLedger(file: file())
        await ledger.record(UsageEvent(.setup, detail: "welcome"))
        #expect(await ledger.drain { _ in throw URLError(.notConnectedToInternet) } == false)
        #expect(await ledger.pendingCount == 1)
        #expect(await ledger.drain { _ in throw UsageLedger.Rejected() })
        #expect(await ledger.pendingCount == 0)
    }

    @Test("When the queue is full, daily marks make room before first-day steps")
    func fullQueueKeepsSetupSteps() async {
        let ledger = UsageLedger(file: file())
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        await ledger.record(UsageEvent(.setup, detail: "welcome", on: start))
        for day in 1...UsageLedger.Limits.pending {
            await ledger.record(UsageEvent(.active, detail: "plex", on: start.addingTimeInterval(Double(day) * 86_400)))
        }
        let sent = Sent()
        await ledger.drain { batch in await sent.add(batch) }
        #expect(await sent.events.count == UsageLedger.Limits.pending)
        #expect(await sent.events.first == UsageEvent(.setup, detail: "welcome", on: start))
    }

    private actor Sent {
        var events: [UsageEvent] = []
        func add(_ batch: [UsageEvent]) { events += batch }
    }
}

@Suite("Watch time tally")
struct WatchTimeTallyTests {
    @Test("Each threshold is reported once a day, and a new UTC day starts over")
    func thresholdsOncePerDay() {
        var tally = WatchTimeTally()
        let morning = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(tally.add(10 * 60, at: morning).isEmpty)
        #expect(tally.add(55 * 60, at: morning) == [.quarterHour, .hour])
        #expect(tally.add(60 * 60, at: morning).isEmpty)
        #expect(tally.add(20 * 60, at: morning.addingTimeInterval(86_400)) == [.quarterHour])
    }
}
