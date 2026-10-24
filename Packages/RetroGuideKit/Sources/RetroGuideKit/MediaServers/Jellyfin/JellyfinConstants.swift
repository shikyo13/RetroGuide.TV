import Foundation

/// Jellyfin API paths, header names and tuning constants in one place.
public enum JellyfinAPI {
    /// The port Jellyfin listens on unless its owner changed it.
    public static let defaultPort = 8096
    static let defaultScheme = "http"

    enum Path {
        static let publicInfo = "/System/Info/Public"
        static let userViews = "/UserViews"
        static let items = "/Items"
        static let currentUser = "/Users/Me"
        static let authenticateByName = "/Users/AuthenticateByName"
        static let authenticateWithQuickConnect = "/Users/AuthenticateWithQuickConnect"
        static let quickConnectEnabled = "/QuickConnect/Enabled"
        static let quickConnectInitiate = "/QuickConnect/Initiate"
        static let quickConnectConnect = "/QuickConnect/Connect"
        static let activeEncodings = "/Videos/ActiveEncodings"
        static func item(_ id: String) -> String { "/Items/\(id)" }
        static func playbackInfo(_ id: String) -> String { "/Items/\(id)/PlaybackInfo" }
        static func stream(_ id: String) -> String { "/Videos/\(id)/stream" }
        static func hlsStream(_ id: String) -> String { "/Videos/\(id)/master.m3u8" }
        static func image(_ id: String, type: String) -> String { "/Items/\(id)/Images/\(type)" }
        static func subtitle(itemID: String, sourceID: String, index: Int, format: String) -> String {
            "/Videos/\(itemID)/\(sourceID)/Subtitles/\(index)/0/Stream.\(format)"
        }
    }

    enum Header {
        static let authorization = "Authorization"
        static let accept = "Accept"
        static let contentType = "Content-Type"
        static let json = "application/json"
    }

    enum Query {
        /// Carries the access token on URLs handed to the player and image loader.
        static let apiKey = "ApiKey"
    }

    enum ItemType {
        static let movie = "Movie"
        static let series = "Series"
        static let episode = "Episode"
        static let boxSet = "BoxSet"
    }

    /// `CollectionType` of a user view (library).
    enum CollectionType {
        static let movies = "movies"
        static let shows = "tvshows"
    }

    enum ImageType {
        static let primary = "Primary"
        static let backdrop = "Backdrop"
        static let logo = "Logo"
    }

    enum StreamType {
        static let audio = "Audio"
        static let subtitle = "Subtitle"
        static let video = "Video"
    }

    /// Keys of a item's `ProviderIds`.
    enum Provider {
        static let imdb = "Imdb"
        static let tmdb = "Tmdb"
        static let tvdb = "Tvdb"
    }

    /// Extra fields requested in listings (Jellyfin omits most by default).
    enum Fields {
        static let titles = "ProviderIds,Genres,Studios,ProductionLocations,DateCreated,Overview,OfficialRating"
        static let playable = titles + ",MediaSources"
        static let idsOnly = "ParentId"
    }

    /// `SubtitleMode` values of a user's configuration.
    enum SubtitleMode {
        static let always = "Always"
        static let smart = "Smart"
        static let onlyForced = "OnlyForced"
        static let none = "None"
    }

    enum Transcode {
        static let videoCodec = "h264,hevc"
        static let audioCodec = "aac,ac3,eac3"
        static let segmentContainer = "ts"
        static let maxAudioChannels = "6"
        static let maxVideoBitrate = "40000000"
    }

    public enum Defaults {
        /// Items requested per page when paging through a library.
        static let pageSize = 500
        /// Maximum simultaneous requests to one server while indexing.
        static let maxConcurrentRequests = 6
        static let requestTimeout: TimeInterval = 30
        /// Short timeout used when probing whether an address answers.
        public static let probeTimeout: TimeInterval = 4
        /// Track selection is fetched while tuning, so it must never hold up playback for long.
        static let trackSelectionTimeout: TimeInterval = 2
        /// Jellyfin counts time in ticks of 100 nanoseconds.
        static let ticksPerSecond: TimeInterval = 10_000_000
        /// How often to ask whether a Quick Connect code was approved.
        public static let quickConnectPollInterval: Duration = .seconds(3)
        /// Name for a track Jellyfin gives no title or language for.
        static let unknownTrackTitle = "Unknown"
        /// Image quality (percent) asked of the server's resizer.
        static let imageQuality = "90"
    }
}
