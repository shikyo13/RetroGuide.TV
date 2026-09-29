import Foundation

/// The library as *titles* (a show with all its episodes, or a movie) rather
/// than individual items: what lineup generation reasons about.
struct TitleCatalog {
    struct Title {
        let id: String
        let isShow: Bool
        /// Positions of the title's schedulable items in ``LibraryIndex/items``.
        let positions: [Int]
        let categories: Set<GenreCategory>
        /// Decade the title premiered in.
        let decade: Int?
        let hours: Double
    }

    let titles: [Title]

    init(index: LibraryIndex) {
        var grouped: [String: [Int]] = [:]
        var order: [String] = []
        for (position, item) in index.items.enumerated() where item.duration >= ScheduleConstants.minimumProgramDuration {
            let id = item.seriesID ?? item.id
            if grouped[id] == nil {
                order.append(id)
            }
            grouped[id, default: []].append(position)
        }
        titles = order.map { id in
            let positions = grouped[id] ?? []
            let categories = positions.reduce(into: Set<GenreCategory>()) { $0.formUnion(index.attributes[$1].categories) }
            let decade = positions.compactMap { index.attributes[$0].decade }.min()
            let seconds = positions.reduce(0) { $0 + index.items[$1].duration }
            return Title(
                id: id,
                isShow: index.items[positions[0]].seriesID != nil,
                positions: positions,
                categories: categories,
                decade: decade,
                hours: seconds / ScheduleConstants.secondsPerHour
            )
        }
    }
}
