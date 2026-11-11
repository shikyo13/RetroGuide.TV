import Foundation
import RetroGuideKit

/// Anonymous setup and usage steps (see ``UsageEvent``).
extension AppModel {
    func recordUsage(_ name: UsageEvent.Name, detail: String = UsageEvent.noDetail) {
        PurchaseAttribution.shared.record(UsageEvent(name, detail: detail))
    }

    /// The app is in use today, and which kinds of server it has.
    func recordActive() {
        recordUsage(.active, detail: UsageEvent.serverKinds(servers.accounts.map(\.kind)))
    }

    /// A program is playing, from a Plex or a Jellyfin server.
    func recordWatching() {
        let serverID = tuner.program?.item.serverID
        let kind = servers.accounts.first { $0.id == serverID }?.kind
        recordUsage(.watched, detail: kind?.rawValue ?? UsageEvent.noDetail)
    }
}
