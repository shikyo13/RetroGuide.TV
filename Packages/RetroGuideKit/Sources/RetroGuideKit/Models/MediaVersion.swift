import Foundation

/// One playable file of an item. A title can have several versions on a server
/// (for example a 4K and a 1080p copy, or a Plex "Optimized Version").
public struct MediaVersion: Codable, Sendable, Hashable {
    /// The server's index for this version (Plex `mediaIndex`).
    public let index: Int
    /// File container, e.g. `"mkv"` or `"mp4"`.
    public let container: String?
    public let videoCodec: String?
    public let audioCodec: String?
    /// Server-relative path of the file itself (Plex part key).
    public let filePath: String?
    /// Vertical resolution in pixels, when known.
    public let height: Int?
    /// Overall bitrate in kilobits per second, when known.
    public let bitrateKbps: Int?

    public init(
        index: Int = .zero,
        container: String?,
        videoCodec: String?,
        audioCodec: String?,
        filePath: String?,
        height: Int? = nil,
        bitrateKbps: Int? = nil
    ) {
        self.index = index
        self.container = container
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.filePath = filePath
        self.height = height
        self.bitrateKbps = bitrateKbps
    }
}

/// How a stream reaches the player.
public enum StreamMethod: String, Sendable, Hashable {
    /// The original file, untouched. No server work.
    case directPlay
    /// Repackaged by the server into HLS; video is copied and only
    /// incompatible audio is converted.
    case directStream
}

/// What the app's active player can open, so servers can skip transcoding.
public struct PlaybackCapabilities: Sendable, Hashable {
    /// The player demuxes and decodes any container/codec itself (e.g. libmpv),
    /// so the original file can always be played directly.
    public let playsAnyFile: Bool

    public init(playsAnyFile: Bool) {
        self.playsAnyFile = playsAnyFile
    }

    /// Apple's AVFoundation: only the formats in ``DirectPlayPolicy``.
    public static let appleNative = PlaybackCapabilities(playsAnyFile: false)
    /// A bundled universal player.
    public static let universal = PlaybackCapabilities(playsAnyFile: true)
}

/// Decides whether a file can be played as-is by a player with given capabilities.
public enum DirectPlayPolicy {
    static let containers: Set<String> = ["mp4", "m4v", "mov"]
    static let videoCodecs: Set<String> = ["h264", "hevc"]
    static let audioCodecs: Set<String> = ["aac", "ac3", "eac3", "alac", "mp3"]

    public static func canDirectPlay(_ info: MediaVersion?, with capabilities: PlaybackCapabilities = .appleNative) -> Bool {
        guard let info, info.filePath != nil else { return false }
        if capabilities.playsAnyFile {
            return true
        }
        guard let container = info.container?.lowercased(), let video = info.videoCodec?.lowercased() else {
            return false
        }
        let audioIsCompatible = info.audioCodec.map { audioCodecs.contains($0.lowercased()) } ?? true
        return containers.contains(container) && videoCodecs.contains(video) && audioIsCompatible
    }
}
