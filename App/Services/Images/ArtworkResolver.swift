import RetroTVKit
import SwiftUI

/// Turns server-relative artwork references into sized URLs.
/// Injected through the environment so views stay decoupled from server clients.
struct ArtworkResolver: Sendable {
    let resolve: @Sendable (_ serverID: String, _ reference: String, _ size: ImageSize) -> URL?

    static let unavailable = ArtworkResolver { _, _, _ in nil }

    func url(serverID: String, reference: String?, size: ImageSize) -> URL? {
        guard let reference else { return nil }
        return resolve(serverID, reference, size)
    }
}

private struct ArtworkResolverKey: EnvironmentKey {
    static let defaultValue = ArtworkResolver.unavailable
}

extension EnvironmentValues {
    var artworkResolver: ArtworkResolver {
        get { self[ArtworkResolverKey.self] }
        set { self[ArtworkResolverKey.self] = newValue }
    }
}

/// Standard artwork request sizes (in pixels) so the server and cache see few variants.
enum ArtworkSize {
    static let backdrop = ImageSize(width: 1_280, height: 720)
    static let logo = ImageSize(width: 800, height: 310)
    static let poster = ImageSize(width: 400, height: 600)
    static let thumbnail = ImageSize(width: 480, height: 270)
}
