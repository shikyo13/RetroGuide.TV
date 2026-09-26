import Foundation

/// Which existing copy of a title to play. RetroGuide.TV never asks the server
/// to convert video; this only chooses between files the server already has.
public enum VideoQuality: String, Codable, Sendable, CaseIterable, Hashable {
    case original
    case upTo1080p
    case upTo720p
    case smallest

    public var displayName: String {
        switch self {
        case .original: "Original"
        case .upTo1080p: "Up to 1080p"
        case .upTo720p: "Up to 720p"
        case .smallest: "Smallest available"
        }
    }

    public var explanation: String {
        switch self {
        case .original: "Always the highest-quality copy. Best for servers in your home."
        case .upTo1080p: "Skips 4K copies when a 1080p or smaller copy exists. Good for most remote servers."
        case .upTo720p: "Prefers 720p or smaller copies. For slow connections."
        case .smallest: "Always the smallest copy the server has."
        }
    }

    /// Tallest version allowed before falling back to the smallest one, if capped.
    var maximumHeight: Int? {
        switch self {
        case .original, .smallest: nil
        case .upTo1080p: Resolution.fullHD
        case .upTo720p: Resolution.hd
        }
    }

    private enum Resolution {
        static let fullHD = 1_080
        static let hd = 720
    }
}

/// How much video the player reads ahead.
public enum BufferProfile: String, Codable, Sendable, Hashable {
    case standard
    /// Reads much further ahead to ride out slow or uneven connections.
    case extended
}

/// Per-server playback preferences, set in Settings → Servers.
public struct ServerPlaybackSettings: Codable, Sendable, Hashable {
    public var quality: VideoQuality
    public var extraBuffering: Bool

    public init(quality: VideoQuality, extraBuffering: Bool) {
        self.quality = quality
        self.extraBuffering = extraBuffering
    }

    /// Defaults for a server on the home network.
    public static let local = ServerPlaybackSettings(quality: .original, extraBuffering: false)
    /// Defaults for a server reached over the internet.
    public static let remote = ServerPlaybackSettings(quality: .upTo1080p, extraBuffering: true)

    public var bufferProfile: BufferProfile {
        extraBuffering ? .extended : .standard
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quality = (try? container.decode(VideoQuality.self, forKey: .quality)) ?? Self.local.quality
        extraBuffering = (try? container.decode(Bool.self, forKey: .extraBuffering)) ?? Self.local.extraBuffering
    }
}

/// Picks which version of a title to play for a quality preference.
public enum MediaVersionSelector {
    public static func best(of versions: [MediaVersion], for quality: VideoQuality) -> MediaVersion? {
        ranked(versions, for: quality).first
    }

    /// Every version, most preferred first, so playback can fall back when the
    /// preferred copy is unavailable (for example deleted from the server's disk).
    public static func ranked(_ versions: [MediaVersion], for quality: VideoQuality) -> [MediaVersion] {
        let ascending = versions.sorted { ($0.height ?? .zero, $0.bitrateKbps ?? .zero) < ($1.height ?? .zero, $1.bitrateKbps ?? .zero) }
        switch quality {
        case .original:
            return ascending.reversed()
        case .smallest:
            return ascending
        case .upTo1080p, .upTo720p:
            // The best copy within the limit first, then smaller ones, then the
            // smallest copies above the limit.
            let limit = quality.maximumHeight ?? .max
            let withinLimit = ascending.filter { ($0.height ?? .zero) <= limit }
            let aboveLimit = ascending.filter { ($0.height ?? .zero) > limit }
            return withinLimit.reversed() + aboveLimit
        }
    }
}
