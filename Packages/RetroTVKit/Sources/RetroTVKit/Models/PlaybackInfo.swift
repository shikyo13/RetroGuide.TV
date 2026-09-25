import Foundation

/// Technical details of an item's primary media file, used to pick the
/// cheapest way to play it (see ``DirectPlayPolicy``).
public struct PlaybackInfo: Codable, Sendable, Hashable {
    /// File container, e.g. `"mkv"` or `"mp4"`.
    public let container: String?
    public let videoCodec: String?
    public let audioCodec: String?
    /// Server-relative path of the file itself (Plex part key).
    public let filePath: String?

    public init(container: String?, videoCodec: String?, audioCodec: String?, filePath: String?) {
        self.container = container
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.filePath = filePath
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

    public static func canDirectPlay(_ info: PlaybackInfo?, with capabilities: PlaybackCapabilities = .appleNative) -> Bool {
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
