import Foundation
import Testing
@testable import RetroGuideKit

/// Cases that once went wrong in scheduling and cross-server merging.
@Suite("Scheduling and merging regressions")
struct SchedulingRegressionTests {
    // A: a blocked long show hides a free short one beyond the look-ahead.
    @Test func cycleFindsFreeShowBeyondLookahead() {
        let items = TestFactory.show("A", episodes: 600) + TestFactory.show("B", episodes: 1)
        let context = ScheduleContext(channelID: "c", items: items, grid: .continuous)
        var picker = CyclePicker(ordering: .syndication, context: context)
        let showA = context.showOfItem[0]
        // Advance until B has just aired.
        var offset: TimeInterval = 0
        for _ in 0..<2_000 {
            let item = picker.next(at: offset, in: context) { _ in true }
            offset += context.slotLengths[item]
            if context.showOfItem[item] != showA { break }
        }
        let next = picker.next(at: offset, in: context) { context.showOfItem[$0] != showA }
        #expect(context.showOfItem[next] != showA, "aired blocked show A although B was free")
    }

    // B: greedy first pick takes the only show another channel can air.
    @Test func greedyAllocation() {
        let a = TestFactory.show("A", episodes: 30)
        let b = TestFactory.show("B", episodes: 30)
        for order in [["x", "y"], ["y", "x"]] {
            let members = order.map { id in (ScheduleContext(channelID: id, items: id == "x" ? a + b : a, grid: .continuous), ScheduleOrdering.syndication) }
            let coordinator = SimulcastCoordinator(limit: 1, channels: members)
            let day = DateInterval(start: ScheduleConstants.epoch, duration: 86_400)
            let programs = members.indices.flatMap { coordinator.timeline(for: $0).programs(overlapping: day) }
            let clashes = programs.filter { p in programs.contains { $0 != p && $0.channelID != p.channelID && $0.item.showID == p.item.showID && $0.start < p.slotEnd && p.start < $0.slotEnd } }
            #expect(clashes.isEmpty, "order \(order): \(clashes.count) clashing programs")
        }
    }

    private func episode(_ server: String, _ key: String, show: String, showGuid: String?, number: Int, guid: String?) -> MediaItem {
        MediaItem(serverID: server, itemKey: key, externalID: guid, libraryID: "\(server)/1", kind: .episode, title: "E\(number)",
                  series: SeriesInfo(key: show, title: "Show", seasonNumber: 1, episodeNumber: number, externalID: showGuid), duration: 1_320)
    }

    private func snapshot(_ server: String, _ items: [MediaItem]) -> LibrarySnapshot {
        LibrarySnapshot(serverID: server, serverName: server, libraries: [MediaLibrary(serverID: server, key: "1", title: "TV", kind: .shows)], items: items)
    }

    // C: one copy has an episode guid, the other only the show guid.
    @Test func mixedEpisodeIdentifiers() {
        let index = LibraryIndex(snapshots: [
            snapshot("home", [episode("home", "h1", show: "10", showGuid: "plex://show/s", number: 1, guid: "plex://episode/e1")]),
            snapshot("friend", [episode("friend", "f1", show: "77", showGuid: "plex://show/s", number: 1, guid: nil)]),
        ])
        #expect(index.items.count == 1)
    }

    // D: the first server lacks the show guid but episodes share guids with the second.
    @Test func showAliasFromEpisodeGuids() {
        let index = LibraryIndex(snapshots: [
            snapshot("home", [1, 2].map { episode("home", "h\($0)", show: "10", showGuid: nil, number: $0, guid: "plex://episode/e\($0)") }),
            snapshot("friend", [1, 2, 3].map { episode("friend", "f\($0)", show: "77", showGuid: "plex://show/s", number: $0, guid: "plex://episode/e\($0)") }),
        ])
        #expect(Set(index.items.map(\.showID)).count == 1, "\(index.items.map(\.showID))")
    }

    // G: a custom rule saved with the second server's show id.
    @Test func ruleWithDroppedServerShowID() {
        let index = LibraryIndex(snapshots: [
            snapshot("home", [1, 2].map { episode("home", "h\($0)", show: "10", showGuid: "plex://show/s", number: $0, guid: "plex://episode/e\($0)") }),
            snapshot("friend", [1, 2].map { episode("friend", "f\($0)", show: "77", showGuid: "plex://show/s", number: $0, guid: "plex://episode/e\($0)") }),
        ])
        #expect(ChannelRule(seriesIDs: ["friend/77"]).matchingItems(in: index).count == 2)
    }

    // J: after a block ends, made-up turns air back to back.
    @Test func madeUpTurnsAreSpread() {
        let items = TestFactory.show("A", episodes: 12) + TestFactory.show("B", episodes: 12) + TestFactory.show("C", episodes: 12)
        let context = ScheduleContext(channelID: "c", items: items, grid: .continuous)
        var picker = CyclePicker(ordering: .syndication, context: context)
        let showA = context.showOfItem[0]
        var aired: [Int] = []
        for turn in 0..<24 {
            let blocked = turn < 9
            aired.append(context.showOfItem[picker.next(at: 0, in: context) { !blocked || context.showOfItem[$0] != showA }])
        }
        let afterBlock = aired.dropFirst(9)
        let longestRun = afterBlock.reduce(into: (run: 0, best: 0, last: -1)) { state, show in
            state.run = show == state.last ? state.run + 1 : 1
            state.best = max(state.best, state.run)
            state.last = show
        }.best
        #expect(longestRun <= 2, "\(aired)")
    }
}
