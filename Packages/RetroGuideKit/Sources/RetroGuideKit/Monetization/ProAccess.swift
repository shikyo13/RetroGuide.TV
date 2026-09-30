import Foundation

/// What the free version includes and what RetroGuide Pro unlocks.
///
/// Free is the whole core experience: one server, every automatic channel,
/// one custom channel, the guide, search and the full player. Pro adds more
/// servers, unlimited custom channels, every theme, schedule controls and no ads.
public struct ProAccess: Sendable, Hashable {
    public enum FreeLimits {
        public static let servers = 1
        public static let customChannels = 1
    }

    public let isPro: Bool

    public init(isPro: Bool) {
        self.isPro = isPro
    }

    public func canAddServer(connectedCount: Int) -> Bool {
        isPro || connectedCount < FreeLimits.servers
    }

    public func canCreateCustomChannel(existingCount: Int) -> Bool {
        isPro || existingCount < FreeLimits.customChannels
    }

    /// Changing a channel's schedule order and aligning program start times.
    public var canChangeScheduling: Bool {
        isPro
    }

    /// Audio and subtitle choices for a whole library at once (like PASTA's
    /// "Apply to Library"); episodes, seasons and shows are free.
    public var canChooseTracksForLibrary: Bool {
        isPro
    }

    /// Ads appear only in the free version (on iPhone and iPad).
    public var showsAds: Bool {
        !isPro
    }
}
