import Foundation
import Testing
@testable import RetroTVKit

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

    @Test("Syndication alternates between shows")
    func syndicationAlternates() {
        var generator = SeededGenerator(seed: 1)
        let firstFour = PlaylistArranger.arrange(items, ordering: .syndication, using: &generator)
            .prefix(4)
            .map { items[$0].headline }
        #expect(Set(firstFour.prefix(3)).count == 3)
    }
}
