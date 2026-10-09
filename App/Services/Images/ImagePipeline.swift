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

    /// Readable from any thread, so views can check it without waiting on the actor.
    private nonisolated let memoryCache = ImageMemoryCache(costLimit: Limits.memoryCacheBytes)

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

    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    /// How many callers are waiting on each download; at zero it's cancelled.
    private var waiters: [String: Int] = [:]

    /// The image at `url` if it's already in memory, without waiting.
    nonisolated func cachedImage(for url: URL, maxPixelSize: Int) -> UIImage? {
        memoryCache.image(forKey: Self.key(url, maxPixelSize))
    }

    /// Returns the image at `url`, downsampled so its longest side is at most
    /// `maxPixelSize`. Downloads and decodes run in parallel, off the actor;
    /// one nobody is waiting for any more (a row scrolled away) is cancelled.
    func image(for url: URL, maxPixelSize: Int) async -> UIImage? {
        let key = Self.key(url, maxPixelSize)
        if let cached = memoryCache.image(forKey: key) {
            return cached
        }
        let task: Task<UIImage?, Never>
        if let existing = inFlight[key] {
            task = existing
        } else {
            let session = session
            task = Task.detached(priority: .userInitiated) {
                guard let (data, _) = try? await session.data(from: url), !Task.isCancelled else { return nil }
                return Self.downsample(data, maxPixelSize: maxPixelSize)
            }
            inFlight[key] = task
        }
        waiters[key, default: .zero] += 1
        let image = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { await self.abandon(key) }
        }
        guard !Task.isCancelled else { return nil }
        waiters[key, default: 1] -= 1
        if waiters[key] ?? .zero <= .zero {
            waiters[key] = nil
        }
        if inFlight[key] == task {
            inFlight[key] = nil
        }
        if let image {
            memoryCache.insert(image, forKey: key, cost: Self.cost(of: image))
        }
        return image
    }

    /// A caller stopped waiting; cancels the download once nobody is.
    private func abandon(_ key: String) {
        waiters[key, default: 1] -= 1
        guard waiters[key] ?? .zero <= .zero else { return }
        waiters[key] = nil
        inFlight.removeValue(forKey: key)?.cancel()
    }

    private nonisolated static func key(_ url: URL, _ maxPixelSize: Int) -> String {
        "\(url.absoluteString)#\(maxPixelSize)"
    }

    private nonisolated static func downsample(_ data: Data, maxPixelSize: Int) -> UIImage? {
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

    private nonisolated static func cost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 1 }
        return cgImage.bytesPerRow * cgImage.height
    }
}

/// Decoded images in memory, limited by cost and purged by the system under
/// pressure. `NSCache` is documented as thread-safe.
final class ImageMemoryCache: @unchecked Sendable {
    private let cache = NSCache<NSString, UIImage>()

    init(costLimit: Int) {
        cache.totalCostLimit = costLimit
    }

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func insert(_ image: UIImage, forKey key: String, cost: Int) {
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
}
