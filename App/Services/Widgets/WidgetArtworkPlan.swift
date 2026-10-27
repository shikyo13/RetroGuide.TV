import CryptoKit
import Foundation
import RetroGuideKit

/// Stable artwork identities shared by every airing that uses the same server image.
struct WidgetArtworkPlan: Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case backdrop, still, logo
    }

    struct Asset: Hashable, Sendable {
        let serverID: String
        let reference: String
        let kind: Kind

        var file: String {
            let identity = "v2|\(serverID)|\(kind.rawValue)|\(reference)"
            return SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }

    let assets: [Asset]

    init(_ item: MediaItem) {
        let artwork = item.artwork
        assets = Kind.allCases.compactMap { kind in
            let reference: String?
            switch kind {
            case .backdrop: reference = artwork.backdrop ?? artwork.thumbnail ?? artwork.poster
            case .still: reference = artwork.thumbnail
            case .logo: reference = artwork.logo
            }
            return reference.map { Asset(serverID: item.serverID, reference: $0, kind: kind) }
        }
    }

    func file(for kind: Kind) -> String? {
        assets.first { $0.kind == kind }?.file
    }
}
