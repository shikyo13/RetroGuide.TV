import Foundation
import RetroGuideKit

struct GuideParams: Decodable, Sendable {
    let from: Date
    let to: Date
    /// Only these channels; every visible channel when omitted.
    let channelIDs: [String]?
}

struct GuideRow: Encodable, Sendable {
    let channelID: String
    let programs: [ProgramInfo]
}

/// One airing, with artwork resolved to image addresses.
struct ProgramInfo: Encodable, Sendable {
    let id: String
    let itemID: String
    let showID: String
    let kind: String
    let start: Date
    /// When the program's own content ends (an intermission may follow).
    let contentEnd: Date
    /// When the next program starts.
    let end: Date
    /// The show name for episodes, the title for movies.
    let headline: String
    /// "S2 E5 · Title" or the year.
    let subheadline: String?
    let title: String
    let year: Int?
    let contentRating: String?
    /// Who it's for (kids, family, teen, mature, unrated), from its rating.
    let audience: String
    let summary: String?
    let artwork: ArtworkInfo
}

struct ArtworkInfo: Encodable, Sendable {
    let poster: String?
    let backdrop: String?
    let logo: String?
    let thumbnail: String?
}

extension CoreState {
    /// Image sizes requested from servers: big enough for a 1080p guide.
    private enum ArtworkSize {
        static let poster = ImageSize(width: 400, height: 600)
        static let backdrop = ImageSize(width: 1280, height: 720)
        static let logo = ImageSize(width: 800, height: 310)
        static let thumbnail = ImageSize(width: 640, height: 360)
    }

    func guide(_ params: GuideParams) -> [GuideRow] {
        let interval = DateInterval(start: params.from, end: max(params.from, params.to))
        let wanted = params.channelIDs.map(Set.init)
        return visibleChannels
            .filter { channel in wanted.map { ids in ids.contains { channel.isIdentified(by: $0) } } ?? true }
            .map { channel in
                GuideRow(channelID: channel.id, programs: channel.timeline.programs(overlapping: interval).map(programInfo))
            }
    }

    func programInfo(_ program: ScheduledProgram) -> ProgramInfo {
        let item = program.item
        return ProgramInfo(
            id: program.id,
            itemID: item.id,
            showID: item.showID,
            kind: item.kind.rawValue,
            start: program.start,
            contentEnd: program.contentEnd,
            end: program.slotEnd,
            headline: item.headline,
            subheadline: item.subheadline,
            title: item.title,
            year: item.year,
            contentRating: item.contentRating,
            audience: item.audience.rawValue,
            summary: item.summary,
            artwork: artwork(of: item)
        )
    }

    func posterURL(of item: MediaItem) -> String? {
        item.artwork.poster.flatMap { clients[item.serverID]?.imageURL(for: $0, size: ArtworkSize.poster)?.absoluteString }
    }

    private func artwork(of item: MediaItem) -> ArtworkInfo {
        let client = clients[item.serverID]
        func url(_ reference: String?, _ size: ImageSize) -> String? {
            reference.flatMap { client?.imageURL(for: $0, size: size)?.absoluteString }
        }
        return ArtworkInfo(
            poster: url(item.artwork.poster, ArtworkSize.poster),
            backdrop: url(item.artwork.backdrop, ArtworkSize.backdrop),
            logo: url(item.artwork.logo, ArtworkSize.logo),
            thumbnail: url(item.artwork.thumbnail, ArtworkSize.thumbnail)
        )
    }
}
