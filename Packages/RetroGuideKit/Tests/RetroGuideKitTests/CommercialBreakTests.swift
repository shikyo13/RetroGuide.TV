import XCTest
@testable import RetroGuideKit

final class CommercialBreakTests: XCTestCase {
    func item(_ key: String, duration: Double) -> MediaItem {
        MediaItem(serverID: "server", itemKey: key, libraryID: "server/library", kind: .movie, title: key, duration: duration)
    }
    var ads: [MediaItem] { [item("a", duration: 30), item("b", duration: 15.173), item("c", duration: 30.372)] }
    func testExactLengthsAcrossEveryGridAndRestoration() throws {
        let definition = ChannelDefinition(id: "regular", number: 1, name: "Regular", rule: ChannelRule(), source: .custom)
        let items = [item("movie", duration: 230)]
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for count in CommercialBreakSettings.Count.allCases {
            let catalog = CommercialCatalog(items: ads, count: count)
            for grid in ScheduleGrid.allCases {
                let original = Channel(definition: definition, items: items, isHidden: false, grid: grid)
                let enabled = Channel(definition: definition, items: items, isHidden: false, grid: grid, commercials: catalog)
                let restored = Channel(definition: definition, items: items, isHidden: false, grid: grid)
                let program = try XCTUnwrap(enabled.timeline.program(at: now))
                let plan = CommercialBreakPlan(program: program)
                XCTAssertEqual(plan.clips.count, count.rawValue)
                XCTAssertEqual(program.contentEnd.timeIntervalSince(program.start), 230, accuracy: 0.001)
                let total = plan.clips.reduce(0) { $0 + $1.item.duration }
                XCTAssertGreaterThanOrEqual(program.slotEnd.timeIntervalSince(program.contentEnd) + 0.001, total)
                if grid == .continuous { XCTAssertEqual(program.slotEnd.timeIntervalSince(program.contentEnd), total, accuracy: 0.001) }
                XCTAssertEqual(original.timeline.program(at: now), restored.timeline.program(at: now))
                XCTAssertEqual(enabled.definition, original.definition)
            }
        }
    }
    func testSelectionsSurviveReorderedCatalogRebuildsAndRetries() throws {
        let catalog = CommercialCatalog(items: ads, count: .two)
        let reordered = CommercialCatalog(items: ads.reversed(), count: .two)
        let program = item("program", duration: 100)
        XCTAssertEqual(catalog, reordered)
        XCTAssertEqual(catalog.selection(channelID: "one", program: program), reordered.selection(channelID: "one", program: program))
        let selected = catalog.selection(channelID: "one", program: program)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let airing = ScheduledProgram(channelID: "one", item: program, start: start, contentEnd: start.addingTimeInterval(100), slotEnd: start.addingTimeInterval(100 + selected.reduce(0) { $0 + $1.duration }), cycle: 0, slot: 0, commercials: selected)
        let plan = CommercialBreakPlan(program: airing)
        let late = plan.clips[1].start.addingTimeInterval(3)
        XCTAssertEqual(plan.clip(at: late)?.position(at: late), 3)
        XCTAssertEqual(CommercialBreakPlan(program: airing).clips.map(\.item), selected)
        XCTAssertNil(plan.clip(at: airing.slotEnd.addingTimeInterval(0.001)))
    }
    func testSparseInvalidAndDuplicateCatalogDoesNotInventFillerOrRepeatClips() {
        let only = ads[2]
        let catalog = CommercialCatalog(items: [only, only, item("bad", duration: .nan), item("too-long", duration: 1_000)], count: .three)
        XCTAssertEqual(catalog.selection(channelID: "a", program: only), [only])
        XCTAssertEqual(catalog.duration(channelID: "a", program: only), 30.372)
        XCTAssertEqual(CommercialCatalog.empty.duration(channelID: "a", program: only), 0)
    }
    func testSharedSchedulesUseExactBreaksWithoutChangingMembership() throws {
        let items = (0..<8).map { item("movie-\($0)", duration: 300 + Double($0)) }
        let index = LibraryIndex(items: items)
        var options = LineupOptions(minimumChannelRuntime: 0, minimumChannelItems: 1)
        let definitions = [ChannelDefinition(id: "all", number: 1, name: "All", rule: ChannelRule(), source: .custom)]
        let baseline = LineupBuilder(curated: definitions, options: options).build(index: index, customization: LineupCustomization())
        options.commercials = CommercialCatalog(items: ads, count: .two)
        let enabled = LineupBuilder(curated: definitions, options: options).build(index: index, customization: LineupCustomization())
        XCTAssertEqual(baseline.map(\.definition), enabled.map(\.definition))
        XCTAssertEqual(baseline.map { $0.items.map(\.id) }, enabled.map { $0.items.map(\.id) })
        for channel in enabled {
            var program = try XCTUnwrap(channel.timeline.program(at: .now))
            for _ in 0..<20 {
                XCTAssertEqual(program.slotEnd.timeIntervalSince(program.contentEnd), program.commercials.reduce(0) { $0 + $1.duration }, accuracy: 0.001)
                let next = try XCTUnwrap(channel.timeline.program(after: program))
                XCTAssertEqual(next.start, program.slotEnd)
                program = next
            }
        }
    }
    func testOldSettingsAndInvalidCountsDefaultSafely() throws {
        let legacy = Data(#"{"isEnabled":true,"libraryIDs":["server/4"],"length":60}"#.utf8)
        let settings = try JSONDecoder().decode(CommercialBreakSettings.self, from: legacy)
        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(settings.count, .one)
        XCTAssertEqual(try JSONDecoder().decode(CommercialBreakSettings.self, from: Data(#"{"count":99}"#.utf8)).count, .one)
    }
}
