import CryptoKit
import Foundation

/// Sidecar subtitle files downloaded ahead of handing them to mpv.
///
/// mpv fetches a subtitle URL itself only after the video file has opened,
/// and the picture waits for it: a slow server turned that into many seconds
/// of no signal. Downloading here instead lets video start at once; the
/// subtitles join when the file arrives, or never, if it doesn't.
final class SubtitleFileCache: Sendable {
    private enum Defaults {
        static let folderName = "Subtitles"
        static let requestTimeout: TimeInterval = 15
        /// Files kept between launches; the rest (oldest first) are removed.
        static let maxFiles = 50
        static let fallbackExtension = "sub"
    }

    static let shared = SubtitleFileCache()

    private let folder: URL
    private let session: URLSession

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        folder = caches.appending(path: Defaults.folderName, directoryHint: .isDirectory)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Defaults.requestTimeout
        session = URLSession(configuration: configuration)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        prune()
    }

    /// The downloaded copy of `url`, if there is one.
    func cachedFile(for url: URL) -> URL? {
        let file = localFile(for: url)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    /// Downloads `url`, returning the local copy, or `nil` if it couldn't be fetched.
    func download(_ url: URL) async -> URL? {
        if let file = cachedFile(for: url) { return file }
        guard let (temporary, response) = try? await session.download(from: url),
              HTTPStatus.success.contains((response as? HTTPURLResponse)?.statusCode ?? .zero)
        else { return nil }
        let file = localFile(for: url)
        try? FileManager.default.removeItem(at: file)
        guard (try? FileManager.default.moveItem(at: temporary, to: file)) != nil else { return nil }
        return file
    }

    /// Named after the address, so the same subtitles are reused across tunes.
    private func localFile(for url: URL) -> URL {
        let name = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let fileExtension = url.pathExtension.isEmpty ? Defaults.fallbackExtension : url.pathExtension
        return folder.appending(path: name).appendingPathExtension(fileExtension)
    }

    private func prune() {
        let key = URLResourceKey.contentModificationDateKey
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [key]),
              files.count > Defaults.maxFiles
        else { return }
        let newestFirst = files.sorted {
            let first = (try? $0.resourceValues(forKeys: [key]).contentModificationDate) ?? .distantPast
            let second = (try? $1.resourceValues(forKeys: [key]).contentModificationDate) ?? .distantPast
            return first > second
        }
        newestFirst.dropFirst(Defaults.maxFiles).forEach { try? FileManager.default.removeItem(at: $0) }
    }
}

private enum HTTPStatus {
    static let success = 200..<300
}
