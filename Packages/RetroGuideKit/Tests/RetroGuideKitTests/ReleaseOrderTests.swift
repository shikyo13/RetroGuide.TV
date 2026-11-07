import Foundation
import Testing
@testable import RetroGuideKit

@Suite("Release Order")
struct ReleaseOrderTests {
    private static let day: TimeInterval = 86_400

    /// Film `number` of a series released in `year` (exact date unless `yearOnly`).
    private func film(_ number: Int, year: Int, yearOnly: Bool = false, addedAt: Date? = nil) -> MediaItem {
        MediaItem(
            serverID: TestFactory.serverID, itemKey: "film\(number)", libraryID: TestFactory.libraryID, kind: .movie,
            title: "Film \(number)", year: year,
            released: yearOnly ? nil : DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "UTC"), year: year, month: 6, day: 1).date,
            duration: 2 * 3_600, addedAt: addedAt
        )
    }

    private func channel(_ items: [MediaItem], ordering: ScheduleOrdering) -> Channel {
        let definition = ChannelDefinition(id: "custom.series", number: ChannelNumbering.custom.lowerBound, name: "Series", rule: ChannelRule(), ordering: ordering, source: .custom)
        return Channel(definition: definition, items: items, isHidden: false, grid: .continuous)
    }

    private func numbers(_ channel: Channel, from start: Date, days: TimeInterval) -> [Int] {
        channel.timeline.programs(overlapping: DateInterval(start: start, duration: days * Self.day)).map { Int($0.item.itemKey.dropFirst(4))! }
    }

    @Test("A film series plays oldest first, then starts over")
    func filmSeriesInOrder() {
        // Listed out of order; one film has only a year.
        let films = [film(3, year: 2004), film(1, year: 2001), film(8, year: 2011), film(5, year: 2007, yearOnly: true),
                     film(2, year: 2002), film(7, year: 2010), film(4, year: 2005), film(6, year: 2009)]
        let aired = numbers(channel(films, ordering: .releaseOrder), from: Date(timeIntervalSince1970: 1_800_000_000), days: 10)
        #expect(aired.count > 16)
        for (previous, next) in zip(aired, aired.dropFirst()) {
            #expect(next == previous % 8 + 1, "film \(previous) was followed by film \(next)")
        }
    }

    @Test("A film added later airs in its place without moving the one on the air")
    func addedFilmJoinsInOrder() {
        // In the past: dates far ahead count as bad metadata (always there).
        let added = Date.now.addingTimeInterval(-10 * Self.day)
        let films = (1...6).filter { $0 != 3 }.map { film($0, year: 2000 + $0) } + [film(3, year: 2003, addedAt: added)]
        let series = channel(films, ordering: .releaseOrder)
        let withoutIt = channel(films.filter { $0.itemKey != "film3" }, ordering: .releaseOrder)
        // Before the film joins, the schedule is exactly the one without it.
        let before = DateInterval(start: added.addingTimeInterval(-3 * Self.day), duration: 3 * Self.day)
        #expect(series.timeline.programs(overlapping: before) == withoutIt.timeline.programs(overlapping: before))
        // Afterwards every film follows the one before it, 2 → 3 → 4 included.
        let aired = numbers(series, from: added.addingTimeInterval(2 * Self.day), days: 6)
        #expect(aired.contains(3))
        for (previous, next) in zip(aired, aired.dropFirst()) {
            #expect(next == previous % 6 + 1, "film \(previous) was followed by film \(next)")
        }
    }

    @Test("Block Shuffle never airs a movie twice in a row")
    func blockShuffleMovies() {
        let films = (1...8).map { film($0, year: 2000 + $0) }
        let aired = numbers(channel(films, ordering: .blockShuffle), from: Date(timeIntervalSince1970: 1_800_000_000), days: 14)
        let repeats = zip(aired, aired.dropFirst()).filter { $0 == $1 }.count
        #expect(repeats == 0)
    }

    @Test("Synced settings name only orders that versions before Release Order can read")
    func syncedOrdersStayReadable() throws {
        let legacy: Set<String> = ["shuffle", "blockShuffle", "syndication", "marathon"]
        var shared = SharedSettings()
        shared.lineup.defaultOrdering = .releaseOrder
        shared.lineup.orderingOverrides = ["curated.scifi": .releaseOrder, "curated.drama": .marathon]
        shared.lineup.customChannels = [ChannelDefinition(id: "custom.hp", number: ChannelNumbering.custom.lowerBound, name: "HP", rule: ChannelRule(), ordering: .releaseOrder, source: .custom)]
        let values = try shared.encoded()
        for (key, data) in values.entries {
            let json = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            let ordering: String? = if key.hasPrefix("lineup/custom/") {
                (json as? [String: Any])?["ordering"] as? String
            } else if key.hasPrefix("lineup/order/") || key == "lineup/defaultOrder" {
                json as? String
            } else {
                nil
            }
            if let ordering { #expect(legacy.contains(ordering), "\(key) stores \(ordering)") }
        }
        let read = try SharedSettings(values: values)
        #expect(read.lineup.defaultOrdering == .releaseOrder)
        #expect(read.lineup.orderingOverrides == ["curated.scifi": .releaseOrder, "curated.drama": .marathon])
        #expect(read.lineup.customChannels.map(\.ordering) == [.releaseOrder])
    }
}
