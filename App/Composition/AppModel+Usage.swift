import Foundation
import RetroGuideKit

/// Setup and usage steps (see ``UsageEvent``).
extension AppModel {
    func recordUsage(_ name: UsageEvent.Name, detail: String = UsageEvent.noDetail) {
        PurchaseAttribution.shared.record(UsageEvent(name, detail: detail))
    }

    /// An event about what the player in use did, such as `apple.timeout`.
    func recordPlayerUsage(_ name: UsageEvent.Name, _ value: some RawRepresentable<String>) {
        recordUsage(name, detail: UsageEvent.detail(currentPlayer, value))
    }

    /// The app is in use today, and which kinds of server it has. Not before
    /// the saved servers are loaded, or it would say there are none.
    func recordActive() {
        guard phase != .launching else { return }
        recordActiveWithLoadedServers()
    }

    /// At launch, once the saved servers are loaded.
    func recordActiveWithLoadedServers() {
        recordUsage(.active, detail: UsageEvent.serverKinds(servers.accounts.map(\.kind)))
    }

    /// Keeps the daily marks right for an app left open across midnight UTC
    /// (an Apple TV playing all evening): opening the app and starting a program
    /// mark the day, but neither happens again when the day turns over. Marks
    /// already made today are dropped before sending, so repeating them is free.
    func markDayWhileOpen() {
        guard !isInBackground else { return }
        recordActive()
        if tuner.signal == .live { recordWatching() }
        recordWatchTime(watchTime.flush())
    }

    /// A program is playing, from a Plex or a Jellyfin server, in one of the players.
    func recordWatching() {
        let serverID = tuner.program?.item.serverID
        let kind = servers.accounts.first { $0.id == serverID }?.kind
        recordUsage(.watched, detail: kind?.rawValue ?? UsageEvent.noDetail)
        recordUsage(.played, detail: currentPlayer.rawValue)
    }

    /// Buffering, or a stream cut off and rejoined, at home or away.
    func recordStall(at location: UsageEvent.Location) {
        recordUsage(.playbackStalled, detail: location.rawValue)
        recordPlayerUsage(.playerStalled, location)
    }

    /// Starts or stops counting today's playing time with the signal.
    func countWatchTime() {
        recordWatchTime(watchTime.playing(tuner.signal == .live))
    }

    private func recordWatchTime(_ crossed: [UsageEvent.WatchTime]) {
        for threshold in crossed { recordUsage(.watchTime, detail: threshold.rawValue) }
    }

    private var currentPlayer: UsageEvent.Player {
        switch tuner.engine.kind {
        case .universal: .retroguide
        case .appleNative: .apple
        }
    }
}
