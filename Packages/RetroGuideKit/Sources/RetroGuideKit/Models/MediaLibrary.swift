import Foundation

/// A library (Plex "section") on a media server.
public struct MediaLibrary: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case movies
        case shows
        /// Music, photos and other libraries RetroGuide cannot schedule.
        case unsupported
    }

    /// Globally unique identifier: `"<serverID>/<libraryKey>"`.
    public let id: String
    public let serverID: String
    public let key: String
    public let title: String
    public let kind: Kind

    public init(serverID: String, key: String, title: String, kind: Kind) {
        self.id = "\(serverID)/\(key)"
        self.serverID = serverID
        self.key = key
        self.title = title
        self.kind = kind
    }

    public var isSchedulable: Bool {
        kind != .unsupported
    }
}
