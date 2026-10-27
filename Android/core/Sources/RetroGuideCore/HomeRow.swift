import Foundation
import RetroGuideKit

/// A channel on the TV's home screen row, with what's on it now.
struct HomeRowEntry: Encodable, Sendable {
    let channelID: String
    let number: Int
    let name: String
    let program: ProgramInfo?
}

struct HomeRowSettings: Encodable, Sendable {
    /// Favorites rather than recent channels (RetroGuide Pro).
    let usesFavorites: Bool
    let hasFavorites: Bool
}

extension CoreState {
    /// The channels for the home screen row (the Apple app's Top Shelf): favorites
    /// with Pro when chosen, otherwise recently watched channels, then the rest.
    func homeRow() -> [HomeRowEntry] {
        let ordered = visibleChannels.sorted { $0.number < $1.number }
        let selected: [Channel]
        if isPro && viewing.topShelfFavorites {
            selected = ordered.filter(viewing.isFavorite)
        } else {
            let recent = viewing.recentChannelIDs.compactMap { id in ordered.first { $0.isIdentified(by: id) } }
            selected = recent + ordered.filter { channel in !recent.contains { $0.id == channel.id } }
        }
        let now = Date.now
        return selected.prefix(ViewingPreferences.Limits.widgetChannels).map { channel in
            HomeRowEntry(
                channelID: channel.id,
                number: channel.number,
                name: channel.name,
                program: channel.timeline.program(at: now).map(programInfo)
            )
        }
    }

    func homeRowSettings() -> HomeRowSettings {
        HomeRowSettings(usesFavorites: viewing.topShelfFavorites, hasFavorites: visibleChannels.contains(where: viewing.isFavorite))
    }

    func setHomeRowFavorites(_ params: EnabledParams) -> HomeRowSettings {
        viewing.topShelfFavorites = params.isEnabled
        store?.save(viewing, file: CoreStore.File.viewing)
        return homeRowSettings()
    }

    /// Remembers a channel the viewer watched, for the home screen row.
    func rememberChannel(_ id: String) {
        viewing.remember(id)
        store?.save(viewing, file: CoreStore.File.viewing)
    }
}
