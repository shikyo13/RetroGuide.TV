import Foundation

/// Plex API paths, header names and tuning constants in one place.
public enum PlexAPI {
    public static let accountBaseURL = URL(string: "https://plex.tv")!
    public static let linkPageURL = URL(string: "https://plex.tv/link")!
    /// Guids from Plex's online agents; identical across servers.
    static let globalGuidPrefix = "plex://"

    enum Path {
        static let pins = "/api/v2/pins"
        static let resources = "/api/v2/resources"
        static let user = "/api/v2/user"
        static let identity = "/identity"
        static let sections = "/library/sections"
        static func sectionItems(_ section: String) -> String { "/library/sections/\(section)/all" }
        static func sectionFilter(_ section: String, _ field: String) -> String { "/library/sections/\(section)/\(field)" }
        static func sectionCollections(_ section: String) -> String { "/library/sections/\(section)/collections" }
        static func collectionChildren(_ key: String) -> String { "/library/collections/\(key)/children" }
        static let transcodeStart = "/video/:/transcode/universal/start.m3u8"
        static let playbackDecision = "/video/:/transcode/universal/decision"
        static let transcodeStop = "/video/:/transcode/universal/stop"
        static let photoTranscode = "/photo/:/transcode"
        static func metadata(_ key: String) -> String { "/library/metadata/\(key)" }
    }

    enum Header {
        static let token = "X-Plex-Token"
        static let product = "X-Plex-Product"
        static let version = "X-Plex-Version"
        static let clientIdentifier = "X-Plex-Client-Identifier"
        static let sessionIdentifier = "X-Plex-Session-Identifier"
        static let clientProfileExtra = "X-Plex-Client-Profile-Extra"
        static let clientProfileName = "X-Plex-Client-Profile-Name"
        static let platform = "X-Plex-Platform"
        static let platformVersion = "X-Plex-Platform-Version"
        static let device = "X-Plex-Device"
        static let deviceName = "X-Plex-Device-Name"
        static let containerStart = "X-Plex-Container-Start"
        static let containerSize = "X-Plex-Container-Size"
        static let accept = "Accept"
        static let json = "application/json"
    }

    /// Plex `type` numbers used in library queries.
    enum MetadataType: Int {
        case movie = 1
        case show = 2
        case episode = 4
    }

    /// Plex `streamType` values.
    enum StreamType {
        static let audio = 2
        static let subtitle = 3
    }

    /// Response trimming. Plex returns cast, crew, markers and more by default;
    /// indexing only needs a fraction of that, which matters over the internet.
    enum Trim {
        private static let excludeElements = "excludeElements"
        private static let excludeFields = "excludeFields"

        /// For full listings: keep genres, countries, images and media versions.
        static let listing = [
            URLQueryItem(name: excludeElements, value: "Role,Director,Writer,Producer,Similar,Label,Guid,UltraBlurColors,Marker,Chapter"),
            URLQueryItem(name: excludeFields, value: "file,tagline"),
        ]

        /// For membership lookups, where only `ratingKey` is used.
        static let keysOnly = [
            URLQueryItem(name: excludeElements, value: "Media,Genre,Country,Collection,Role,Director,Writer,Producer,Similar,Label,Guid,Image,UltraBlurColors,Marker,Chapter"),
            URLQueryItem(name: excludeFields, value: "summary,tagline,thumb,art,theme,file"),
        ]
    }

    enum SectionType {
        static let movie = "movie"
        static let show = "show"
    }

    enum FilterField {
        static let genre = "genre"
        static let network = "network"
    }

    enum ImageType {
        static let clearLogo = "clearLogo"
    }

    public enum Defaults {
        /// Items requested per page when paging through a library.
        static let pageSize = 1_000
        /// Maximum simultaneous requests to one server while indexing.
        static let maxConcurrentRequests = 10
        static let requestTimeout: TimeInterval = 30
        /// Short timeout used when probing which server address is reachable.
        static let probeTimeout: TimeInterval = 4
        /// Track selection is fetched while tuning, so it must never hold up playback for long.
        static let trackSelectionTimeout: TimeInterval = 2
        /// Asking the server for permission to play a file directly.
        static let playbackDecisionTimeout: TimeInterval = 5
        /// How often to poll plex.tv while waiting for the user to enter a link code.
        public static let pinPollInterval: Duration = .seconds(2)
        static let millisecondsPerSecond: TimeInterval = 1_000
    }

    /// Parameters for the universal transcoder. The client profile extra asks
    /// the server to remux into HLS whenever the video/audio can be copied,
    /// and to transcode only what the Apple TV cannot decode.
    /// Playback decisions: the server authorizes a session to play a file directly.
    enum Decision {
        /// Plex's built-in profiles for Apple platforms describe Apple's own player
        /// (for example stereo only, or at most 1080p), which would reject files
        /// the bundled player handles. The generic profile has no such limits.
        static let genericProfile = "Generic"
        /// Tells the server this client plays any container and codec itself.
        static let directPlayAnythingProfile =
            "add-direct-play-profile(type=videoProfile&protocol=http&container=*&videoCodec=*&audioCodec=*&subtitleCodec=*)"
        static let protocolHTTP = "http"
        /// `generalDecisionCode` when the file can be played as is.
        static let directPlayOK = 1000
    }

    enum Transcode {
        static let protocolHLS = "hls"
        static let maxVideoBitrateKbps = 40_000
        static let videoResolution = "3840x2160"
        static let profileExtra = [
            "add-transcode-target(type=videoProfile&context=streaming&protocol=hls&container=mpegts&videoCodec=h264,hevc&audioCodec=aac,ac3,eac3)",
            "add-limitation(scope=videoAudioCodec&scopeName=*&type=upperBound&name=audio.channels&value=6)",
        ].joined(separator: "+")
    }
}
