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

/// An agent id such as `imdb://tt0944947` (listings include these with `includeGuids`).
struct PlexGuid: Decodable {
    let id: String
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
    let grandparentGuid: String?
    let parentIndex: Int?
    let index: Int?
    let year: Int?
    let duration: Int?
    /// When the item was added to the server (Unix seconds).
    let addedAt: Int?
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
    let guids: [PlexGuid]?

    enum CodingKeys: String, CodingKey {
        case ratingKey, guid, type, title, grandparentRatingKey, grandparentTitle, grandparentGuid
        case parentIndex, index, year, duration, addedAt, summary, contentRating, contentRatingAge
        case studio, thumb, art, grandparentThumb, grandparentArt, childCount
        case genres = "Genre"
        case countries = "Country"
        case images = "Image"
        case media = "Media"
        case guids = "Guid"
    }

    /// Plex agent guids (`plex://…`) are global; local and legacy guids are not.
    var globalGuid: String? {
        Self.global(guid)
    }

    /// The episode's show's global guid, when the listing includes it.
    var grandparentGlobalGuid: String? {
        Self.global(grandparentGuid)
    }

    private static func global(_ guid: String?) -> String? {
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
                bitrateKbps: media.bitrate,
                duration: media.duration.flatMap { $0 > .zero ? TimeInterval($0) / PlexAPI.Defaults.millisecondsPerSecond : nil }
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
    /// Milliseconds.
    let duration: Int?
    let parts: [PlexPart]?

    enum CodingKeys: String, CodingKey {
        case container, videoCodec, audioCodec, height, bitrate, duration
        case parts = "Part"
    }
}

struct PlexPart: Decodable {
    let id: Int?
    let key: String?
    let streams: [PlexStream]?

    enum CodingKeys: String, CodingKey {
        case id, key
        case streams = "Stream"
    }
}

/// One audio, video or subtitle stream of a media part. `selected` reflects the
/// requesting user's language preferences and per-item choices.
struct PlexStream: Decodable {
    /// The server's id for the stream, used to save a track choice.
    var id: Int?
    let streamType: Int
    let index: Int?
    let key: String?
    let selected: Bool?
    /// BCP 47 tag ("en") and ISO 639-2 code ("eng"); either may be missing.
    var languageTag: String?
    var languageCode: String?
    var forced: Bool?
    /// Plex's names for the track: "English (AAC Stereo)", "English (SRT External)"…
    var displayTitle: String?
    var extendedDisplayTitle: String?
    /// The file marks this track as the one to play by default.
    var isDefault: Bool?
    /// "srt", "ass", "idx" (VobSub)…
    var codec: String?

    enum CodingKeys: String, CodingKey {
        case id, streamType, index, key, selected, languageTag, languageCode, forced, displayTitle, extendedDisplayTitle, codec
        case isDefault = "default"
    }

    /// Where to fetch an external subtitle file. A VobSub `.idx` names its
    /// images in a `.sub` beside it, found by swapping the extension, so the
    /// path needs the extension too (Plex serves `/library/streams/<id>.sub`).
    var externalKey: String? {
        guard let key else { return nil }
        return codec == PlexAPI.Subtitle.vobSubIndexCodec ? key + PlexAPI.Subtitle.vobSubIndexExtension : key
    }
}

/// The signed-in plex.tv user (only the language settings are read).
struct PlexUser: Decodable {
    let profile: PlexUserProfile?
}

struct PlexUserProfile: Decodable {
    let defaultAudioLanguage: String?
    let defaultSubtitleLanguage: String?
    /// 0: manually selected, 1: shown with foreign audio, 2: always enabled.
    let autoSelectSubtitle: Int?
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
    /// Whether this device and the server share a public address (same network).
    let publicAddressMatches: Bool?
    let connections: [PlexConnection]?
}

struct PlexConnection: Decodable {
    let uri: String
    let local: Bool
    let relay: Bool
}
