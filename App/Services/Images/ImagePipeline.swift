import ImageIO
import UIKit

/// Loads, downsamples and caches artwork.
///
/// - Memory: decoded images live in a cost-limited `NSCache` that the system
///   purges under pressure. Images are downsampled to the size they are shown
///   at, so a 4K backdrop never sits in memory at full resolution.
/// - Disk: raw responses are cached by `URLCache`, so artwork survives relaunches.
/// - Concurrent requests for the same image share one download.
actor ImagePipeline {
    static let shared = ImagePipeline()

    private enum Limits {
        static let bytesPerMegabyte = 1_024 * 1_024
        static let memoryCacheBytes = 96 * bytesPerMegabyte
        static let urlCacheMemoryBytes = 16 * bytesPerMegabyte
        static let urlCacheDiskBytes = 300 * bytesPerMegabyte
        static let bytesPerPixel = 4
        static let requestTimeout: TimeInterval = 20
    }

    private let memoryCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = Limits.memoryCacheBytes
        return cache
    }()

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: Limits.urlCacheMemoryBytes,
            diskCapacity: Limits.urlCacheDiskBytes
        )
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = Limits.requestTimeout
        return URLSession(configuration: configuration)
    }()

    private var inFlight: [NSString: Task<UIImage?, Never>] = [:]

    /// Returns the image at `url`, downsampled so its longest side is at most `maxPixelSize`.
    func image(for url: URL, maxPixelSize: Int) async -> UIImage? {
        let key = "\(url.absoluteString)#\(maxPixelSize)" as NSString
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }
        if let existing = inFlight[key] {
            return await existing.value
        }
        let session = session
        let task = Task<UIImage?, Never> {
            guard let (data, _) = try? await session.data(from: url) else { return nil }
            return Self.downsample(data, maxPixelSize: maxPixelSize)
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image {
            memoryCache.setObject(image, forKey: key, cost: Self.cost(of: image))
        }
        return image
    }

    private static func downsample(_ data: Data, maxPixelSize: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, .zero, thumbnailOptions) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private static func cost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 1 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
