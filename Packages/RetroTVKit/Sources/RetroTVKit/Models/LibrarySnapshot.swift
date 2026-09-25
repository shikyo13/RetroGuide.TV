import Foundation

/// Everything RetroTV knows about one server's selected libraries at a point in time.
/// Snapshots are cached to disk so the guide appears instantly on launch.
public struct LibrarySnapshot: Codable, Sendable {
    /// Bump when the cached format changes so stale caches are discarded.
    public static let formatVersion = 2

    public let formatVersion: Int
    public let serverID: String
    public let libraries: [MediaLibrary]
    public let items: [MediaItem]
    public let refreshedAt: Date

    public init(serverID: String, libraries: [MediaLibrary], items: [MediaItem], refreshedAt: Date = .now) {
        self.formatVersion = Self.formatVersion
        self.serverID = serverID
        self.libraries = libraries
        self.items = items
        self.refreshedAt = refreshedAt
    }

    public var isCurrentFormat: Bool {
        formatVersion == Self.formatVersion
    }
}
