import Foundation
import RetroGuideKit

struct SearchParams: Decodable, Sendable {
    let query: String
}

/// A show or movie on the channels, and where it airs next.
struct SearchHit: Encodable, Sendable {
    let id: String
    let title: String
    /// `MediaKind` display name ("Show", "Movie").
    let kind: String
    let poster: String?
    let channelID: String?
    let channelNumber: Int?
    let channelName: String?
    let callSign: String?
    /// The airing on now or next, within the next two days.
    let airing: ProgramInfo?
}

extension CoreState {
    func search(_ params: SearchParams) -> [SearchHit] {
        let index = searchIndex ?? ProgramSearchIndex(channels: visibleChannels)
        searchIndex = index
        return index.search(params.query, at: .now).map { result in
            let sample = result.title.sample
            return SearchHit(
                id: result.id,
                title: result.title.title,
                kind: result.title.kind.displayName,
                poster: posterURL(of: sample),
                channelID: result.channel?.id,
                channelNumber: result.channel?.number,
                channelName: result.channel?.name,
                callSign: result.channel?.callSign,
                airing: result.airing.map(programInfo)
            )
        }
    }
}
