import UIKit

/// Reuses artwork while WidgetKit archives successive entries for the same program.
final class WidgetArtworkCache: @unchecked Sendable {
    static let shared = WidgetArtworkCache()

    private enum Limits {
        static let bytes = 6 * 1_024 * 1_024
        static let images = 24
        static let bytesPerPixel = 4
    }

    // NSCache provides thread-safe access and may evict images under memory pressure.
    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = Limits.bytes
        cache.countLimit = Limits.images
        return cache
    }()

    func image(_ file: String?) -> UIImage? {
        guard let file, let url = WhatsOnStore.artworkURL(file) else { return nil }
        if let image = cache.object(forKey: file as NSString) { return image }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        let cost = image.cgImage.map { $0.width * $0.height * Limits.bytesPerPixel } ?? Limits.bytes
        cache.setObject(image, forKey: file as NSString, cost: cost)
        return image
    }
}
