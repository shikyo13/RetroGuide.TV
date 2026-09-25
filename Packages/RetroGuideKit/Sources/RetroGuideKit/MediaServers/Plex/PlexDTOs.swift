import Foundation

// Wire formats for the subset of the Plex API RetroGuide uses. Every field is
// optional unless Plex always sends it, so partial metadata never breaks indexing.

struct PlexEnvelope<Content: Decodable>: Decodable {
    let mediaContainer: Content

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexMetadataPage: Decodable {
    let totalSize: Int?
    let metadata: [PlexMetadata]?

    enum CodingKeys: String, CodingKey {
        case totalSize
        case metadata = "Metadata"
    }
}

struct PlexDirectoryPage: Decodable {
    let directory: [PlexDirectory]?

    enum CodingKeys: String, CodingKey {
        case directory = "Directory"
    }
}

struct PlexDirectory: Decodable {
    let key: String
    let title: String
    let type: String?
}

struct PlexTag: Decodable {
    let tag: String
}

struct PlexImage: Decodable {
    let type: String
    let url: String
}

struct PlexMetadata: Decodable {
    let ratingKey: String
    let guid: String?
    let type: String?
    let title: String
    let grandparentRatingKey: String?
    let grandparentTitle: String?
    let parentIndex: Int?
    let index: Int?
    let year: Int?
    let duration: Int?
    let summary: String?
    let contentRating: String?
    let contentRatingAge: Int?
    let studio: String?
    let thumb: String?
    let art: String?
    let grandparentThumb: String?
    let grandparentArt: String?
    let childCount: Int?
    let genres: [PlexTag]?
    let countries: [PlexTag]?
    let images: [PlexImage]?
    let media: [PlexMedia]?

    enum CodingKeys: String, CodingKey {
        case ratingKey, guid, type, title, grandparentRatingKey, grandparentTitle
        case parentIndex, index, year, duration, summary, contentRating, contentRatingAge
        case studio, thumb, art, grandparentThumb, grandparentArt, childCount
        case genres = "Genre"
        case countries = "Country"
        case images = "Image"
        case media = "Media"
    }

    /// Plex agent guids (`plex://…`) are global; local and legacy guids are not.
    var globalGuid: String? {
        guard let guid, guid.hasPrefix(PlexAPI.globalGuidPrefix) else { return nil }
        return guid
    }

    var clearLogo: String? {
        images?.first { $0.type == PlexAPI.ImageType.clearLogo }?.url
    }

    var versions: [MediaVersion] {
        (media ?? []).enumerated().map { index, media in
            MediaVersion(
                index: index,
                container: media.container,
                videoCodec: media.videoCodec,
                audioCodec: media.audioCodec,
                filePath: media.parts?.first?.key,
                height: media.height,
                bitrateKbps: media.bitrate
            )
        }
    }
}

struct PlexMedia: Decodable {
    let container: String?
    let videoCodec: String?
    let audioCodec: String?
    let height: Int?
    let bitrate: Int?
    let parts: [PlexPart]?

    enum CodingKeys: String, CodingKey {
        case container, videoCodec, audioCodec, height, bitrate
        case parts = "Part"
    }
}

struct PlexPart: Decodable {
    let key: String?
    let streams: [PlexStream]?

    enum CodingKeys: String, CodingKey {
        case key
        case streams = "Stream"
    }
}

/// One audio, video or subtitle stream of a media part. `selected` reflects the
/// requesting user's language preferences and per-item choices.
struct PlexStream: Decodable {
    let streamType: Int
    let index: Int?
    let key: String?
    let selected: Bool?
}

struct PlexPin: Decodable {
    let id: Int
    let code: String
    let authToken: String?
    let expiresIn: Int?
}

struct PlexResource: Decodable {
    let name: String
    let clientIdentifier: String
    let provides: String
    let owned: Bool?
    let accessToken: String?
    let connections: [PlexConnection]?
}

struct PlexConnection: Decodable {
    let uri: String
    let local: Bool
    let relay: Bool
}
