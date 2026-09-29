import Foundation
import Testing
@testable import RetroGuideKit

@Suite("PlaylistArranger")
struct PlaylistArrangerTests {
    private let items = TestFactory.show("Alpha", episodes: 10)
        + TestFactory.show("Beta", episodes: 4)
        + [TestFactory.movie("m1")]

    @Test("Every ordering is a permutation of the input", arguments: ScheduleOrdering.allCases)
    func permutation(ordering: ScheduleOrdering) {
        var generator = SeededGenerator(seed: 42)
        let order = PlaylistArranger.arrange(items, ordering: ordering, using: &generator)
        #expect(order.sorted() == Array(items.indices))
    }

    @Test("Episode order within a show is preserved", arguments: [ScheduleOrdering.blockShuffle, .syndication, .marathon])
    func episodesStayInOrder(ordering: ScheduleOrdering) {
        var generator = SeededGenerator(seed: 7)
        let order = PlaylistArranger.arrange(items, ordering: ordering, using: &generator)
        let alphaNumbers = order
            .map { items[$0] }
            .filter { $0.series?.title == "Alpha" }
            .compactMap(\.series?.episodeNumber)
        #expect(alphaNumbers == Array(1...10))
    }

    @Test("Marathon airs each show contiguously")
    func marathonIsContiguous() {
        var generator = SeededGenerator(seed: 1)
        let shows = PlaylistArranger.arrange(items, ordering: .marathon, using: &generator).map { items[$0].headline }
        let transitions = zip(shows, shows.dropFirst()).filter { $0 != $1 }.count
        #expect(transitions == 2)
    }

    @Test("Syndication never airs the same show twice in a row while others remain")
    func syndicationAlternates() {
        let balanced = TestFactory.show("Alpha", episodes: 6) + TestFactory.show("Beta", episodes: 6) + TestFactory.show("Gamma", episodes: 6)
        var generator = SeededGenerator(seed: 1)
        let shows = PlaylistArranger.arrange(balanced, ordering: .syndication, using: &generator).map { balanced[$0].headline }
        #expect(zip(shows, shows.dropFirst()).allSatisfy { $0 != $1 })
    }

    @Test("Short shows air throughout the cycle, not only at the start", arguments: [ScheduleOrdering.shuffle, .blockShuffle, .syndication])
    func shortShowsAreSpread(ordering: ScheduleOrdering) {
        let mix = TestFactory.show("Long", episodes: 300) + TestFactory.show("Short", episodes: 12)
        for seed in UInt64(1)...20 {
            var generator = SeededGenerator(seed: seed)
            let order = PlaylistArranger.arrange(mix, ordering: ordering, using: &generator)
            let shortPositions = order.enumerated().filter { mix[$0.element].headline == "Short" }.map(\.offset)
            let lastQuarter = order.count * 3 / 4
            #expect(shortPositions.contains { $0 >= lastQuarter })
            #expect(shortPositions.contains { $0 < order.count / 4 })
        }
    }
}
