import Foundation

/// Tunables for automatic lineup generation.
public struct LineupOptions: Sendable, Hashable {
    /// Channels with less total content than this are dropped as too repetitive.
    public var minimumChannelRuntime: TimeInterval
    /// Channels with fewer items than this are dropped.
    public var minimumChannelItems: Int
    /// A show needs at least this many episodes to earn a marathon channel.
    public var marathonMinimumEpisodes: Int
    /// Upper bound on marathon channels (the longest-running shows win).
    public var maximumMarathonChannels: Int
    /// A collection needs at least this many items to become a channel.
    public var collectionMinimumItems: Int
    /// A network needs at least this many different shows to become a channel
    /// (a single-show network would just duplicate that show's marathon).
    public var networkMinimumShows: Int
    /// Alignment of program start times.
    public var grid: ScheduleGrid

    public init(
        minimumChannelRuntime: TimeInterval = Defaults.minimumChannelRuntime,
        minimumChannelItems: Int = Defaults.minimumChannelItems,
        marathonMinimumEpisodes: Int = Defaults.marathonMinimumEpisodes,
        maximumMarathonChannels: Int = Defaults.maximumMarathonChannels,
        collectionMinimumItems: Int = Defaults.collectionMinimumItems,
        networkMinimumShows: Int = Defaults.networkMinimumShows,
        grid: ScheduleGrid = .continuous
    ) {
        self.minimumChannelRuntime = minimumChannelRuntime
        self.minimumChannelItems = minimumChannelItems
        self.marathonMinimumEpisodes = marathonMinimumEpisodes
        self.maximumMarathonChannels = maximumMarathonChannels
        self.collectionMinimumItems = collectionMinimumItems
        self.networkMinimumShows = networkMinimumShows
        self.grid = grid
    }

    public enum Defaults {
        public static let minimumChannelRuntime: TimeInterval = 6 * ScheduleConstants.secondsPerHour
        public static let minimumChannelItems = 4
        public static let marathonMinimumEpisodes = 40
        public static let maximumMarathonChannels = 40
        public static let collectionMinimumItems = 5
        public static let networkMinimumShows = 3
    }
}

/// Channel number ranges per source, so numbers stay stable as libraries change.
public enum ChannelNumbering {
    public static let libraries = 90..<100
    public static let networks = 100..<200
    public static let collections = 200..<300
    public static let marathons = 300..<500
    public static let custom = 500..<1_000
}
