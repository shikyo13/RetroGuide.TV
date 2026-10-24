import Foundation

/// An image as ``Artwork`` stores it for Jellyfin: the item that owns it, the
/// image type and the server's cache tag, encoded as `"<itemID>/<type>/<tag>"`.
struct JellyfinImageReference: Hashable {
    private static let separator: Character = "/"
    private static let partCount = 3

    let itemID: String
    let type: String
    let tag: String

    init(itemID: String, type: String, tag: String) {
        self.itemID = itemID
        self.type = type
        self.tag = tag
    }

    /// `nil` unless the item has a tagged image of that type.
    init?(itemID: String?, type: String, tag: String?) {
        guard let itemID, let tag else { return nil }
        self.init(itemID: itemID, type: type, tag: tag)
    }

    init?(encoded: String) {
        let parts = encoded.split(separator: Self.separator, omittingEmptySubsequences: false)
        guard parts.count == Self.partCount, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        self.init(itemID: String(parts[0]), type: String(parts[1]), tag: String(parts[2]))
    }

    var encoded: String {
        [itemID, type, tag].joined(separator: String(Self.separator))
    }
}
