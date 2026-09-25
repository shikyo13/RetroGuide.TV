import Foundation

public enum ScheduleConstants {
    public static let secondsPerMinute: TimeInterval = 60
    public static let secondsPerHour: TimeInterval = 3_600

    /// All schedules are measured from this fixed instant (2024-01-01T00:00:00Z),
    /// so a channel shows the same program at the same time on every launch
    /// and on every device.
    public static let epoch = Date(timeIntervalSince1970: 1_704_067_200)

    /// Items shorter than this (trailers, extras, broken metadata) are never scheduled.
    public static let minimumProgramDuration: TimeInterval = 2 * secondsPerMinute

    /// Number of recently used schedule cycles each timeline keeps in memory.
    static let cachedCyclesPerChannel = 3

    /// Episodes per show in one block when using ``ScheduleOrdering/blockShuffle``.
    static let blockShuffleEpisodesPerBlock = 3
}
