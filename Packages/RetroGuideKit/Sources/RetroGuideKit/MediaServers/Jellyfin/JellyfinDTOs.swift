import Foundation

// Wire formats for the subset of the Jellyfin API RetroGuide uses. Jellyfin
// writes keys in PascalCase (`ProviderIds`); ``JellyfinCoding`` maps them to
// these camelCase names. Every field is optional unless Jellyfin always sends
// it, so partial metadata never breaks indexing.

struct JellyfinQueryResult<Item: Decodable>: Decodable {
    let items: [Item]?
    let totalRecordCount: Int?
}

struct JellyfinNamedItem: Decodable {
    let name: String
}

struct JellyfinItem: Decodable {
    let id: String
    let name: String?
    let type: String?
    let collectionType: String?
    let parentId: String?
    let childCount: Int?
    let seriesId: String?
    let seriesName: String?
    /// Season number of an episode.
    let parentIndexNumber: Int?
    /// Episode number within its season.
    let indexNumber: Int?
    let runTimeTicks: Int64?
    let productionYear: Int?
    let overview: String?
    let officialRating: String?
    let genres: [String]?
    let studios: [JellyfinNamedItem]?
    let productionLocations: [String]?
    /// ISO 639-1 code of the title's original language, e.g. `"ja"`.
    let originalLanguage: String?
    let providerIds: [String: String]?
    let dateCreated: String?
    let imageTags: [String: String]?
    let backdropImageTags: [String]?
    let seriesPrimaryImageTag: String?
    let parentBackdropItemId: String?
    let parentBackdropImageTags: [String]?
    let parentLogoItemId: String?
    let parentLogoImageTag: String?
    let mediaSources: [JellyfinMediaSource]?
}

struct JellyfinMediaSource: Decodable {
    let id: String
    let container: String?
    /// Overall bitrate in bits per second.
    let bitrate: Int?
    let mediaStreams: [JellyfinMediaStream]?
    /// The tracks the server would play for this viewer (their remembered
    /// choice, else their language settings). `-1` means no subtitles.
    let defaultAudioStreamIndex: Int?
    let defaultSubtitleStreamIndex: Int?
}

struct JellyfinMediaStream: Decodable {
    let type: String?
    /// The stream's index in the container (external subtitles come after the embedded streams).
    let index: Int?
    let codec: String?
    let language: String?
    let title: String?
    let displayTitle: String?
    let isForced: Bool?
    let isDefault: Bool?
    let isExternal: Bool?
    let height: Int?
}

struct JellyfinPlaybackInfo: Decodable {
    let mediaSources: [JellyfinMediaSource]?
}

struct JellyfinPublicInfo: Decodable {
    let id: String
    let serverName: String?
    let version: String?
    let localAddress: String?
    let startupWizardCompleted: Bool?
}

struct JellyfinAuthenticationResult: Decodable {
    let accessToken: String
    let user: JellyfinUser
}

struct JellyfinUser: Decodable {
    let id: String
    let name: String?
    let configuration: JellyfinUserConfiguration?
}

struct JellyfinUserConfiguration: Decodable {
    let audioLanguagePreference: String?
    let subtitleLanguagePreference: String?
    let subtitleMode: String?
}

struct JellyfinQuickConnectState: Decodable {
    let secret: String
    let code: String
    let authenticated: Bool?
}

struct JellyfinPasswordSignIn: Encodable {
    let username: String
    let pw: String
}

struct JellyfinQuickConnectSignIn: Encodable {
    let secret: String
}

/// JSON coding for Jellyfin's PascalCase keys and its seven-digit fractional dates.
enum JellyfinCoding {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { path in
            CodingName(path.last.map { lowercasingFirst($0.stringValue) } ?? "")
        }
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .custom { path in
            CodingName(path.last.map { uppercasingFirst($0.stringValue) } ?? "")
        }
        return encoder
    }()

    /// Parses Jellyfin's `2020-11-21T02:13:52.6503687Z`, whose seven
    /// fractional digits Foundation's ISO 8601 parsing rejects.
    static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        guard let dot = text.firstIndex(of: ".") else { return formatter.date(from: text) }
        let fractionEnd = text[dot...].firstIndex { $0 == "Z" || $0 == "+" || $0 == "-" } ?? text.endIndex
        return formatter.date(from: String(text[..<dot]) + String(text[fractionEnd...]))
    }

    private static func lowercasingFirst(_ key: String) -> String {
        key.prefix(1).lowercased() + key.dropFirst()
    }

    private static func uppercasingFirst(_ key: String) -> String {
        key.prefix(1).uppercased() + key.dropFirst()
    }

    private struct CodingName: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init(_ name: String) {
            stringValue = name
        }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }
    }
}
