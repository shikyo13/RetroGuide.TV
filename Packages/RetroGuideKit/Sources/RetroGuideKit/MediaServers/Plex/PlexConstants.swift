import Foundation

/// Plex API paths, header names and tuning constants in one place.
public enum PlexAPI {
    public static let accountBaseURL = URL(string: "https://plex.tv")!
    public static let linkPageURL = URL(string: "https://plex.tv/link")!

    enum Path {
        static let pins = "/api/v2/pins"
        static let resources = "/api/v2/resources"
        static let identity = "/identity"
        static let sections = "/library/sections"
        static func sectionItems(_ section: String) -> String { "/library/sections/\(section)/all" }
        static func sectionFilter(_ section: String, _ field: String) -> String { "/library/sections/\(section)/\(field)" }
        static func sectionCollections(_ section: String) -> String { "/library/sections/\(section)/collections" }
        static func collectionChildren(_ key: String) -> String { "/library/collections/\(key)/children" }
        static let transcodeStart = "/video/:/transcode/universal/start.m3u8"
        static let transcodeStop = "/video/:/transcode/universal/stop"
        static let photoTranscode = "/photo/:/transcode"
        static func metadata(_ key: String) -> String { "/library/metadata/\(key)" }
    }

    enum Header {
        static let token = "X-Plex-Token"
        static let product = "X-Plex-Product"
        static let version = "X-Plex-Version"
        static let clientIdentifier = "X-Plex-Client-Identifier"
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
        static let maxConcurrentRequests = 6
        static let requestTimeout: TimeInterval = 30
        /// Short timeout used when probing which server address is reachable.
        static let probeTimeout: TimeInterval = 4
        /// Track selection is fetched while tuning, so it must never hold up playback for long.
        static let trackSelectionTimeout: TimeInterval = 2
        /// How often to poll plex.tv while waiting for the user to enter a link code.
        public static let pinPollInterval: Duration = .seconds(2)
        static let millisecondsPerSecond: TimeInterval = 1_000
    }

    /// Parameters for the universal transcoder. The client profile extra asks
    /// the server to remux into HLS whenever the video/audio can be copied,
    /// and to transcode only what the Apple TV cannot decode.
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
