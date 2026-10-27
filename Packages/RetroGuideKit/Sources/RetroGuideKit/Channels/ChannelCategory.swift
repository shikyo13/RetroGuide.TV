import Foundation

/// The kinds of channel in a lineup, by what they're built around. These are
/// the names used everywhere (settings, docs, code):
///
/// - Catch-all channels: everything of a kind (Everything, All Shows, Movies).
/// - Genre channels: curated channels built around a genre or format.
/// - Decade channels: curated channels built around a decade.
/// - Network, collection and library channels: one per network, collection
///   or library in the viewer's own library.
/// - 24/7 channels: one long-running show, nonstop.
/// - Custom channels: made by the viewer.
public enum ChannelCategory: Int, CaseIterable, Sendable, Comparable {
    // Declaration order is lineup order (and duplicate priority).
    case catchAll
    case genre
    case decade
    case network
    case collection
    case library
    case allDay
    case custom

    public init(_ definition: ChannelDefinition) {
        switch definition.source {
        case .curated: self = definition.rule.isCatchAll ? .catchAll : .genre
        case .decade: self = .decade
        case .network: self = .network
        case .collection: self = .collection
        case .library: self = .library
        case .series: self = .allDay
        case .custom: self = .custom
        }
    }

    public static func < (lhs: ChannelCategory, rhs: ChannelCategory) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Channels of this kind need a few different titles to be a channel
    /// rather than one show under a misleading name.
    var needsSeveralTitles: Bool {
        switch self {
        case .genre, .decade, .network, .collection, .library: true
        case .catchAll, .allDay, .custom: false
        }
    }

    /// Places reserved for this kind before the rest of the lineup is filled
    /// round-robin, so no kind crowds out the others. (24/7 channels have
    /// their own limit, ``LineupOptions/maximumMarathonChannels``.)
    var firstPassAllowance: Int {
        switch self {
        case .genre: Allowance.genre
        case .decade: Allowance.decade
        case .network: Allowance.network
        case .collection: Allowance.collection
        case .library: Allowance.library
        case .catchAll, .allDay, .custom: .zero
        }
    }

    private enum Allowance {
        static let genre = 24
        static let decade = 16
        static let network = 16
        static let collection = 12
        static let library = 8
    }
}
