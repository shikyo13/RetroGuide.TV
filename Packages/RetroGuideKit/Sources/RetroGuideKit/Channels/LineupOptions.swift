import Foundation

/// Tunables for automatic lineup generation.
public struct LineupOptions: Sendable, Hashable {
    /// Channels with less total content than this are dropped as too repetitive.
    public var minimumChannelRuntime: TimeInterval
    /// Channels with fewer items than this are dropped.
    public var minimumChannelItems: Int
    /// A show needs at least this many regular seasons to get a 24/7 channel.
    public var marathonMinimumSeasons: Int
    /// 24/7 channels are limited on their own (most episodes first) and don't
    /// take places from the other channels (``maximumChannels``).
    public var maximumMarathonChannels: Int
    /// A collection of movies only needs at least this many to be a channel,
    /// so one film franchise (Alien, Die Hard) isn't a channel of its own.
    public var movieCollectionMinimumTitles: Int
    /// Genre, decade, network, collection and library channels need at least
    /// this many different titles, in libraries with at least
    /// `titleMinimumLibraryTitles` titles (tiny libraries can't fill channels
    /// with several titles each; any channel beats none there). Thin
    /// neighbouring decade channels merge first (``DecadeChannelMerger``).
    public var minimumChannelTitles: Int
    public var titleMinimumLibraryTitles: Int
    /// Channels sharing this much of their combined titles with a channel
    /// earlier in the lineup are near-duplicates and dropped.
    public var nearDuplicateSimilarity: Double
    /// A collection needs at least this many items to become a channel.
    public var collectionMinimumItems: Int
    /// A network needs at least this many different shows to become a channel
    /// (a single-show network would just duplicate that show's marathon).
    public var networkMinimumShows: Int
    /// Upper bound on automatic channels other than 24/7 channels (see
    /// ``LineupSelection``). Custom channels are never dropped.
    public var maximumChannels: Int
    /// Alignment of program start times.
    public var grid: ScheduleGrid

    public init(
        minimumChannelRuntime: TimeInterval = Defaults.minimumChannelRuntime,
        minimumChannelItems: Int = Defaults.minimumChannelItems,
        marathonMinimumSeasons: Int = Defaults.marathonMinimumSeasons,
        maximumMarathonChannels: Int = Defaults.maximumMarathonChannels,
        movieCollectionMinimumTitles: Int = Defaults.movieCollectionMinimumTitles,
        minimumChannelTitles: Int = Defaults.minimumChannelTitles,
        titleMinimumLibraryTitles: Int = Defaults.titleMinimumLibraryTitles,
        nearDuplicateSimilarity: Double = Defaults.nearDuplicateSimilarity,
        collectionMinimumItems: Int = Defaults.collectionMinimumItems,
        networkMinimumShows: Int = Defaults.networkMinimumShows,
        maximumChannels: Int = Defaults.maximumChannels,
        grid: ScheduleGrid = .continuous
    ) {
        self.minimumChannelRuntime = minimumChannelRuntime
        self.minimumChannelItems = minimumChannelItems
        self.marathonMinimumSeasons = marathonMinimumSeasons
        self.maximumMarathonChannels = maximumMarathonChannels
        self.movieCollectionMinimumTitles = movieCollectionMinimumTitles
        self.minimumChannelTitles = minimumChannelTitles
        self.titleMinimumLibraryTitles = titleMinimumLibraryTitles
        self.nearDuplicateSimilarity = nearDuplicateSimilarity
        self.collectionMinimumItems = collectionMinimumItems
        self.networkMinimumShows = networkMinimumShows
        self.maximumChannels = maximumChannels
        self.grid = grid
    }

    /// Options scaled to the library, so small libraries still get a full
    /// lineup and large ones aren't flooded with near-duplicate channels.
    public static func adapted(to index: LibraryIndex, grid: ScheduleGrid) -> LineupOptions {
        let totalRuntime = index.items.reduce(.zero) { $0 + $1.duration }
        let runtime = min(
            max(totalRuntime * Scaling.runtimeFraction, Scaling.minimumChannelRuntime),
            Defaults.minimumChannelRuntime
        )
        return LineupOptions(minimumChannelRuntime: runtime, grid: grid)
    }

    public enum Scaling {
        /// A channel needs at least this share of the whole library's runtime…
        public static let runtimeFraction = 0.004
        /// …but never less than this.
        public static let minimumChannelRuntime: TimeInterval = 2 * ScheduleConstants.secondsPerHour
    }

    public enum Defaults {
        public static let minimumChannelRuntime: TimeInterval = 6 * ScheduleConstants.secondsPerHour
        public static let minimumChannelItems = 4
        public static let marathonMinimumSeasons = 3
        public static let maximumMarathonChannels = 40
        public static let movieCollectionMinimumTitles = 15
        public static let minimumChannelTitles = 3
        public static let titleMinimumLibraryTitles = 40
        public static let nearDuplicateSimilarity = 0.9
        public static let collectionMinimumItems = 5
        public static let networkMinimumShows = 5
        public static let maximumChannels = 120
    }
}

/// Channel number ranges. Automatic channels are numbered consecutively from
/// the start of ``automatic`` in lineup order; the per-source ranges order
/// the channels the library adds (libraries, networks, collections, 24/7).
public enum ChannelNumbering {
    public static let automatic = 1..<500
    public static let libraries = 90..<100
    public static let networks = 100..<200
    public static let collections = 200..<300
    public static let marathons = 300..<500
    public static let custom = 500..<1_000
}
