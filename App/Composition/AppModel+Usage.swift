import Foundation
import RetroGuideKit

/// Setup and usage steps (see ``UsageEvent``).
extension AppModel {
    func recordUsage(_ name: UsageEvent.Name, detail: String = UsageEvent.noDetail) {
        PurchaseAttribution.shared.record(UsageEvent(name, detail: detail))
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

    /// A program is playing, from a Plex or a Jellyfin server.
    func recordWatching() {
        let serverID = tuner.program?.item.serverID
        let kind = servers.accounts.first { $0.id == serverID }?.kind
        recordUsage(.watched, detail: kind?.rawValue ?? UsageEvent.noDetail)
    }
}
