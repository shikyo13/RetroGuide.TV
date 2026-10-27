import Foundation

/// Personal channel choices survive temporary loss of a server or Pro access.
public struct ViewingPreferences: Codable, Equatable, Sendable {
    public enum WidgetSource: String, Codable, CaseIterable, Sendable {
        case recent, favorites, selected, pinned
        public var title: String {
            switch self {
            case .recent: "Last watched & nearby"
            case .favorites: "Favorites"
            case .selected: "Selected channels"
            case .pinned: "One pinned channel"
            }
        }
    }
    public var favoriteIDs: Set<String> = []
    public var favoritesOnly = false
    public var widgetSource: WidgetSource = .recent
    public var widgetChannelIDs: Set<String> = []
    public var pinnedChannelID: String?
    public var topShelfFavorites = false
    public var recentChannelIDs: [String] = []
    public init() {}

    public func isFavorite(_ channel: Channel) -> Bool {
        favoriteIDs.contains(channel.id) || !favoriteIDs.isDisjoint(with: channel.formerIDs)
    }

    public mutating func toggleFavorite(_ channel: Channel) {
        if isFavorite(channel) {
            favoriteIDs.remove(channel.id)
            favoriteIDs.subtract(channel.formerIDs)
        } else {
            favoriteIDs.insert(channel.id)
        }
    }

    public mutating func remember(_ id: String) {
        recentChannelIDs.removeAll { $0 == id }
        recentChannelIDs.insert(id, at: .zero)
        recentChannelIDs = Array(recentChannelIDs.prefix(Limits.recentChannels))
    }

    public enum Limits {
        public static let recentChannels = 8
        public static let widgetChannels = 8
    }
}
