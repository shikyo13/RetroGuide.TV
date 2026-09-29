import Foundation

/// Numbers automatic channels in fixed sections and keeps each channel's number
/// for as long as it exists, so channels don't shuffle when others come and go.
enum ChannelNumberer {
    enum Section: CaseIterable {
        case catchAll, showHomes, movieHomes, spotlights, marathons

        var range: Range<Int> {
            switch self {
            case .catchAll: 1..<10
            case .showHomes: 10..<100
            case .movieHomes: 100..<150
            case .spotlights: 150..<300
            case .marathons: 300..<ChannelNumbering.custom.lowerBound
            }
        }
    }

    /// Numbers past every section, used only when a section overflows.
    static let overflow = 1_000..<10_000

    /// Assigns numbers in list order: a channel's saved number when it's still
    /// free and inside its section, otherwise the lowest free number there.
    static func number(_ entries: [(definition: ChannelDefinition, section: Section)], saved: [String: Int]) -> [ChannelDefinition] {
        var used = Set<Int>()
        var result = entries.map(\.definition)
        var pending: [Int] = []
        for (position, entry) in entries.enumerated() {
            if let number = saved[entry.definition.id], entry.section.range.contains(number), used.insert(number).inserted {
                result[position].number = number
            } else {
                pending.append(position)
            }
        }
        for position in pending {
            let range = entries[position].section.range
            let number = range.first { !used.contains($0) } ?? overflow.first { !used.contains($0) } ?? overflow.upperBound
            used.insert(number)
            result[position].number = number
        }
        return result
    }
}
