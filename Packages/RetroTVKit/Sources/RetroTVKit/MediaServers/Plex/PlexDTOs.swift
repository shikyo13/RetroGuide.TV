import Foundation

// Wire formats for the subset of the Plex API RetroTV uses. Every field is
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
    let images: [PlexImage]?
    let media: [PlexMedia]?

    enum CodingKeys: String, CodingKey {
        case ratingKey, type, title, grandparentRatingKey, grandparentTitle
        case parentIndex, index, year, duration, summary, contentRating, contentRatingAge
        case studio, thumb, art, grandparentThumb, grandparentArt, childCount
        case genres = "Genre"
        case images = "Image"
        case media = "Media"
    }

    var clearLogo: String? {
        images?.first { $0.type == PlexAPI.ImageType.clearLogo }?.url
    }

    var playbackInfo: PlaybackInfo? {
        guard let primary = media?.first else { return nil }
        return PlaybackInfo(
            container: primary.container,
            videoCodec: primary.videoCodec,
            audioCodec: primary.audioCodec,
            filePath: primary.parts?.first?.key
        )
    }
}

struct PlexMedia: Decodable {
    let container: String?
    let videoCodec: String?
    let audioCodec: String?
    let parts: [PlexPart]?

    enum CodingKeys: String, CodingKey {
        case container, videoCodec, audioCodec
        case parts = "Part"
    }
}

struct PlexPart: Decodable {
    let key: String?
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
