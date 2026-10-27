import Foundation
import RetroGuideKit

/// What the "What's On" widget shows (the Apple app's `WhatsOnSnapshot`):
/// channels in rotation order, each with its programs for the next hours.
struct WidgetSnapshot: Encodable, Sendable {
    struct Program: Encodable, Sendable {
        let title: String
        let episode: String?
        let start: Date
        let end: Date
        let still: String?
        let backdrop: String?
        let logo: String?
    }

    struct Channel: Encodable, Sendable {
        let id: String
        let number: Int
        let name: String
        let callSign: String
        let programs: [Program]
    }

    let channels: [Channel]
    /// One pinned channel: no flipping.
    let pinned: Bool
}

struct WidgetSettings: Encodable, Sendable {
    /// `ViewingPreferences.WidgetSource`: recent, favorites, selected or pinned.
    let source: String
    let sources: [OptionsInfo.Choice]
    let selectedIDs: [String]
    let pinnedID: String?
    let hasFavorites: Bool
    let limit: Int
}

struct WidgetSourceParams: Decodable, Sendable {
    let source: String
}

extension CoreState {
    private enum WidgetTuning {
        static let channels = ViewingPreferences.Limits.widgetChannels
        static let horizon: TimeInterval = 12 * ScheduleConstants.secondsPerHour
        static let programsPerChannel = 64
        static let still = ImageSize(width: 640, height: 360)
        static let logo = ImageSize(width: 400, height: 155)
    }

    /// The widget's channels: the one watched last and the next in the guide;
    /// with Pro, favorites, chosen channels or one pinned channel instead.
    func widgetSnapshot(lastChannelID: String?) -> WidgetSnapshot {
        let ordered = visibleChannels.sorted { $0.number < $1.number }
        let start = ordered.firstIndex { channel in lastChannelID.map(channel.isIdentified(by:)) ?? false } ?? .zero
        var selected = Array(ordered[start...] + ordered[..<start])
        var pinned = false
        if isPro {
            switch viewing.widgetSource {
            case .recent: break
            case .favorites: selected = ordered.filter(viewing.isFavorite)
            case .selected: selected = ordered.filter { channel in viewing.widgetChannelIDs.contains(where: channel.isIdentified) }
            case .pinned:
                selected = ordered.filter { $0.isIdentified(by: viewing.pinnedChannelID ?? "") }
                pinned = true
            }
        }
        let window = DateInterval(start: .now, duration: WidgetTuning.horizon)
        return WidgetSnapshot(channels: selected.prefix(WidgetTuning.channels).compactMap { channel in
            let programs = channel.timeline.programs(overlapping: window).prefix(WidgetTuning.programsPerChannel)
            guard !programs.isEmpty else { return nil }
            return WidgetSnapshot.Channel(
                id: channel.id, number: channel.number, name: channel.name, callSign: channel.callSign,
                programs: programs.map { program in
                    let item = program.item
                    let client = clients[item.serverID]
                    func url(_ reference: String?, _ size: ImageSize) -> String? {
                        reference.flatMap { client?.imageURL(for: $0, size: size)?.absoluteString }
                    }
                    return WidgetSnapshot.Program(
                        title: item.headline,
                        episode: item.subheadline,
                        start: program.start,
                        end: program.slotEnd,
                        still: url(item.artwork.thumbnail, WidgetTuning.still),
                        backdrop: url(item.artwork.backdrop, WidgetTuning.still),
                        logo: url(item.artwork.logo, WidgetTuning.logo)
                    )
                }
            )
        }, pinned: pinned)
    }

    func widgetSettings() -> WidgetSettings {
        WidgetSettings(
            source: viewing.widgetSource.rawValue,
            sources: ViewingPreferences.WidgetSource.allCases.map { OptionsInfo.Choice(id: $0.rawValue, title: $0.title) },
            selectedIDs: viewing.widgetChannelIDs.sorted(),
            pinnedID: viewing.pinnedChannelID,
            hasFavorites: visibleChannels.contains(where: viewing.isFavorite),
            limit: ViewingPreferences.Limits.widgetChannels
        )
    }

    func setWidgetSource(_ params: WidgetSourceParams) -> WidgetSettings {
        if let source = ViewingPreferences.WidgetSource(rawValue: params.source) {
            viewing.widgetSource = source
            store?.save(viewing, file: CoreStore.File.viewing)
        }
        return widgetSettings()
    }

    /// Adds or removes a chosen channel, or pins one (depending on the source).
    func toggleWidgetChannel(_ params: ChannelParams) -> WidgetSettings {
        if viewing.widgetSource == .pinned {
            viewing.pinnedChannelID = params.channelID
        } else if viewing.widgetChannelIDs.contains(params.channelID) {
            viewing.widgetChannelIDs.remove(params.channelID)
        } else if viewing.widgetChannelIDs.count < ViewingPreferences.Limits.widgetChannels {
            viewing.widgetChannelIDs.insert(params.channelID)
        }
        store?.save(viewing, file: CoreStore.File.viewing)
        return widgetSettings()
    }
}

struct WidgetParams: Decodable, Sendable {
    let lastChannelID: String?
}
