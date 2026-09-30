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

@Suite("Cross-server identity")
struct CrossServerIdentityTests {
    private func episode(_ server: String, show: String, showGuid: String?, number: Int) -> MediaItem {
        MediaItem(serverID: server, itemKey: "\(server)-\(number)", externalID: "plex://episode/\(number)", libraryID: "\(server)/1", kind: .episode, title: "E\(number)",
                  series: SeriesInfo(key: show, title: "Show", seasonNumber: 1, episodeNumber: number, externalID: showGuid), duration: 1_320)
    }

    private func snapshot(_ server: String, _ items: [MediaItem]) -> LibrarySnapshot {
        LibrarySnapshot(serverID: server, serverName: server, libraries: [MediaLibrary(serverID: server, key: "1", title: "TV", kind: .shows)], items: items)
    }

    /// A knows the show; A and B share episode 1, B and C share episode 2; C has episode 3.
    private func snapshots() -> [LibrarySnapshot] {
        [
            snapshot("a", [episode("a", show: "10", showGuid: "plex://show/s", number: 1)]),
            snapshot("b", [episode("b", show: "20", showGuid: nil, number: 1), episode("b", show: "20", showGuid: nil, number: 2)]),
            snapshot("c", [episode("c", show: "30", showGuid: nil, number: 2), episode("c", show: "30", showGuid: nil, number: 3)]),
        ]
    }

    @Test("A chain of servers resolves to one show, whatever the order", arguments: 0..<30)
    func chainIsStable(seed: Int) {
        var generator = SeededGenerator(seed: UInt64(seed))
        let shuffled = snapshots().shuffled(using: &generator).map {
            LibrarySnapshot(serverID: $0.serverID, serverName: $0.serverName, libraries: $0.libraries, items: $0.items.shuffled(using: &generator))
        }
        let index = LibraryIndex(snapshots: shuffled)
        #expect(Set(index.items.map(\.showID)) == ["plex://show/s"])
    }

    @Test("Shows linked to two different global ids are left alone")
    func conflictingIDs() {
        let index = LibraryIndex(snapshots: [
            snapshot("a", [episode("a", show: "10", showGuid: "plex://show/one", number: 1)]),
            snapshot("b", [episode("b", show: "20", showGuid: nil, number: 1), episode("b", show: "20", showGuid: nil, number: 2)]),
            snapshot("c", [episode("c", show: "30", showGuid: "plex://show/two", number: 2)]),
        ])
        #expect(index.items.contains { $0.showID == "b/20" })
    }
}

@Suite("Fair turns on small channels")
struct FairTurnsTests {
    private static let items = TestFactory.show("Long", episodes: 500) + TestFactory.show("Short1", episodes: 6) + TestFactory.show("Short2", episodes: 6)

    private static func airings(_ ordering: ScheduleOrdering, count: Int) -> [MediaItem] {
        let context = ScheduleContext(channelID: "c", items: items, grid: .continuous)
        var picker = ChannelPicker(ordering: ordering, context: context)
        return (0..<count).map { _ in context.items[picker.next(at: .zero, in: context) { _ in true }] }
    }

    @Test("Each show gets an equal share of turns, whatever its episode count", arguments: [ScheduleOrdering.syndication, .shuffle, .blockShuffle])
    func equalShares(ordering: ScheduleOrdering) {
        let aired = Self.airings(ordering, count: 600)
        let longShare = Double(aired.filter { $0.headline == "Long" }.count) / Double(aired.count)
        #expect(abs(longShare - 1.0 / 3.0) < 0.05, "Long show had \(longShare)")
    }

    @Test("Every order keeps each show's episodes in order", arguments: ScheduleOrdering.allCases)
    func episodesInOrder(ordering: ScheduleOrdering) {
        // Each show starts wherever the channel starts it, then runs in order.
        var next: [String: Int] = [:]
        for item in Self.airings(ordering, count: 600) {
            let number = item.series?.episodeNumber ?? 0
            let expected = next[item.headline] ?? number
            #expect(number == expected || number == 1, "\(item.headline) jumped to \(number)")
            next[item.headline] = number + 1
        }
    }
}
