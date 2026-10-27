import Foundation
import RetroGuideKit

struct OrderingParams: Decodable, Sendable {
    let channelID: String
    /// A ``ScheduleOrdering``.
    let ordering: String
}

struct TitleParams: Decodable, Sendable {
    let channelID: String
    let showID: String
}

struct HiddenParams: Decodable, Sendable {
    let channelID: String
    let isHidden: Bool
}

struct EnabledParams: Decodable, Sendable {
    let isEnabled: Bool
}

struct ViewingInfo: Encodable, Sendable {
    let favoritesOnly: Bool
}

extension CoreState {
    // MARK: - Lineup

    /// Changes the lineup settings, saves them and rebuilds the channels.
    /// Nothing changes while parental controls lock Settings. With the parental
    /// custom lineup on, changes go to that lineup.
    func updateCustomization(_ change: (inout LineupCustomization) -> Void) -> [ChannelInfo] {
        guard !isParentalLocked else { return channelList() }
        if parentalPolicy.isEnabled && parentalPolicy.usesCustomLineup {
            change(&parentalPolicy.channelCustomization)
            store?.save(parentalPolicy, file: CoreStore.File.parental)
        } else {
            change(&customization)
            store?.saveCustomization(customization)
        }
        rebuildChannels()
        return channelList()
    }

    func setOrdering(_ params: OrderingParams) throws -> [ChannelInfo] {
        guard let ordering = ScheduleOrdering(rawValue: params.ordering), let channel = channel(withID: params.channelID) else {
            throw CoreError.unknownChannel
        }
        let id = channel.definition.id
        return updateCustomization { customization in
            if let index = customization.customChannels.firstIndex(where: { $0.id == id }) {
                customization.customChannels[index].ordering = ordering
            } else {
                customization.orderingOverrides[id] = ordering
            }
        }
    }

    /// Takes a show (or movie) off one channel; it stays on every other channel.
    func removeTitle(_ params: TitleParams) -> [ChannelInfo] {
        updateCustomization { $0.removedTitles[params.channelID, default: []].insert(params.showID) }
    }

    func restoreTitle(_ params: TitleParams) -> [ChannelInfo] {
        updateCustomization { customization in
            customization.removedTitles[params.channelID]?.remove(params.showID)
            if customization.removedTitles[params.channelID]?.isEmpty == true {
                customization.removedTitles[params.channelID] = nil
            }
        }
    }

    func setHidden(_ params: HiddenParams) -> [ChannelInfo] {
        let formerIDs = channels.first { $0.id == params.channelID }?.formerIDs ?? []
        return updateCustomization { customization in
            if params.isHidden {
                customization.hiddenChannelIDs.insert(params.channelID)
            } else {
                // A channel hidden under an earlier id is shown again too.
                customization.hiddenChannelIDs.remove(params.channelID)
                customization.hiddenChannelIDs.subtract(formerIDs)
            }
        }
    }

    // MARK: - Personal

    func toggleFavorite(_ params: ChannelParams) throws -> [ChannelInfo] {
        guard let channel = channel(withID: params.channelID) else { throw CoreError.unknownChannel }
        viewing.toggleFavorite(channel)
        store?.save(viewing, file: CoreStore.File.viewing)
        return channelList()
    }

    func setFavoritesOnly(_ params: EnabledParams) -> ViewingInfo {
        viewing.favoritesOnly = params.isEnabled
        store?.save(viewing, file: CoreStore.File.viewing)
        return viewingInfo()
    }

    func viewingInfo() -> ViewingInfo {
        ViewingInfo(favoritesOnly: viewing.favoritesOnly)
    }

    func setPro(_ params: EnabledParams) -> Done {
        isPro = params.isEnabled
        return Done()
    }
}
