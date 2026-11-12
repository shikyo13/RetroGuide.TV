import Foundation
import Testing
@testable import RetroGuideKit

/// Release Order across synced devices, including ones on 1.8, which don't
/// know it: the newest choice has to win everywhere.
@Suite("Release Order sync")
struct ReleaseOrderSyncTests {
    private static let channel = "curated.scifi"

    /// A device as the app's iCloud sync drives it: local edits are diffed
    /// against what it last applied; received records replace its settings.
    private struct Device {
        /// Emulates 1.8: never writes or reads the full-order records.
        let isLegacy: Bool
        var replica = SettingsReplica()
        var baseline = SettingsValues()
        var lineup = LineupCustomization()

        init(legacy: Bool = false) { isLegacy = legacy }

        var order: ScheduleOrdering? { lineup.orderingOverrides[ReleaseOrderSyncTests.channel] }

        private func local() throws -> SettingsValues {
            var shared = SharedSettings()
            shared.lineup = lineup
            return visible(try shared.encoded())
        }

        private func visible(_ values: SettingsValues) -> SettingsValues {
            isLegacy ? SettingsValues(values.entries.filter { !$0.key.contains("Flag") }) : values
        }

        mutating func choose(_ ordering: ScheduleOrdering) throws {
            lineup.orderingOverrides[ReleaseOrderSyncTests.channel] = ordering
            let current = try local()
            try replica.capture(current, comparedTo: baseline)
            baseline = current
        }

        mutating func receive(from other: Device) throws {
            for record in other.replica.records.values.sorted(by: { $0.key < $1.key }) { try replica.merge(record) }
            lineup = try SharedSettings(values: visible(replica.values)).lineup
            baseline = try local()
        }
    }

    @Test("Two devices: the newest choice wins after Release Order")
    func twoDevices() throws {
        var a = Device(), b = Device()
        try a.choose(.shuffle)
        try b.receive(from: a)
        // Release Order on A while B, not yet synced, changes the same channel twice.
        try a.choose(.releaseOrder)
        try b.choose(.syndication)
        try b.choose(.blockShuffle)
        try a.receive(from: b); try b.receive(from: a)
        #expect(a.order == b.order)
        try b.choose(.marathon)
        try a.receive(from: b); try b.receive(from: a)
        #expect(a.order == .marathon)
        #expect(b.order == .marathon)
    }

    @Test("A 1.8 device's change wins, and Marathon chosen afterwards stays Marathon")
    func olderDeviceInBetween() throws {
        var a = Device(), old = Device(legacy: true)
        try a.choose(.releaseOrder)
        try old.receive(from: a)
        #expect(old.order == .marathon)
        try old.choose(.shuffle)
        try a.receive(from: old)
        #expect(a.order == .shuffle)
        try a.choose(.marathon)
        try old.receive(from: a); try a.receive(from: old)
        #expect(a.order == .marathon)
        try a.choose(.releaseOrder)
        try old.receive(from: a); try a.receive(from: old)
        #expect(a.order == .releaseOrder)
        #expect(old.order == .marathon)
    }
}
