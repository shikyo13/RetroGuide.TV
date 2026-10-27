import Foundation
import Testing
@testable import RetroGuideKit

/// The schedule of a real library: run with `RETROGUIDE_SNAPSHOT=<library
/// snapshot plist>` (skipped otherwise; `RETROGUIDE_GRID=30` for the
/// half-hour grid), in release:
/// `swift test -c release -Xswiftc -enable-testing --filter RealLibrarySchedule`.
@Suite("Real library schedule")
struct RealLibraryScheduleTests {
    @Test("Rules, period switches and speed")
    func report() throws {
        guard let path = ProcessInfo.processInfo.environment["RETROGUIDE_SNAPSHOT"] else { return }
        let snapshot = try PropertyListDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let index = LibraryIndex(snapshots: [snapshot], quality: [snapshot.serverID: .original])
        let grid = ScheduleGrid(rawValue: Int(ProcessInfo.processInfo.environment["RETROGUIDE_GRID"] ?? "") ?? 0) ?? .continuous
        print(ScheduleDiagnostics.report(index: index, curated: try ChannelCatalog.curated(), grid: grid, customization: LineupCustomization(simulcastLimit: .two)))
    }
}
