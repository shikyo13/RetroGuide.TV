import Foundation

/// Paces full-screen ads in the free version: at most one per stretch of
/// watching, counted in time actually spent watching rather than wall-clock
/// time, so opening the app briefly never triggers one.
public struct AdPacing: Codable, Sendable, Hashable {
    /// Watching time between full-screen ads.
    public static let interstitialInterval: TimeInterval = 90 * ScheduleConstants.secondsPerMinute

    public private(set) var watchedSinceInterstitial: TimeInterval

    public init(watchedSinceInterstitial: TimeInterval = .zero) {
        self.watchedSinceInterstitial = max(watchedSinceInterstitial, .zero)
    }

    public var isInterstitialDue: Bool {
        watchedSinceInterstitial >= Self.interstitialInterval
    }

    public mutating func recordWatching(_ duration: TimeInterval) {
        guard duration > .zero else { return }
        watchedSinceInterstitial += duration
    }

    public mutating func interstitialShown() {
        watchedSinceInterstitial = .zero
    }
}
