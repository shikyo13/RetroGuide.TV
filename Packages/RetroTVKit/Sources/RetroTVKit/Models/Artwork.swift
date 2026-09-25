import Foundation

/// Server-relative artwork references. The owning `MediaServerClient`
/// resolves them into sized URLs with ``MediaServerClient/imageURL(for:size:)``.
public struct Artwork: Codable, Sendable, Hashable {
    /// Portrait poster (show poster for episodes).
    public let poster: String?
    /// Wide background art.
    public let backdrop: String?
    /// Transparent title logo ("clear logo").
    public let logo: String?
    /// Episode still or movie poster, used for small tiles.
    public let thumbnail: String?

    public init(poster: String? = nil, backdrop: String? = nil, logo: String? = nil, thumbnail: String? = nil) {
        self.poster = poster
        self.backdrop = backdrop
        self.logo = logo
        self.thumbnail = thumbnail
    }
}

/// Requested pixel size for server-side image resizing.
public struct ImageSize: Sendable, Hashable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}
