import Foundation

/// The subtitle timing last set for each show. A season's subtitles usually
/// come from one source and are off by the same amount, so the next episode
/// starts with the correction the last one needed. Only the most recently
/// adjusted shows are kept.
public struct ShowSubtitleOffsets: Codable, Sendable, Equatable {
    /// Shows remembered; adjusting another one forgets the longest unadjusted.
    public static let capacity = 200

    private struct Entry: Codable, Sendable, Equatable {
        let show: String
        let offset: TimeInterval
    }

    /// Oldest adjustment first.
    private var entries: [Entry] = []

    public init() {}

    public var count: Int {
        entries.count
    }

    public subscript(show: String) -> TimeInterval? {
        entries.last { $0.show == show }?.offset
    }

    /// Remembers `offset` for `show`; original timing forgets the show.
    public mutating func set(_ offset: TimeInterval, for show: String) {
        entries.removeAll { $0.show == show }
        guard offset != .zero else { return }
        entries.append(Entry(show: show, offset: offset))
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
    }
}
