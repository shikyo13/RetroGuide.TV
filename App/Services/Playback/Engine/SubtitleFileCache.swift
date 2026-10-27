import CryptoKit
import Foundation
import RetroGuideKit

/// Downloads sidecars without holding up video. Multi-file formats are cached
/// as one entry so the player never receives an incomplete subtitle set.
final class SubtitleFileCache: Sendable {
    private enum Defaults {
        static let folderName = "Subtitles"
        static let fileName = "subtitle"
        static let requestTimeout: TimeInterval = 15
        /// Complete entries kept between launches; the oldest are removed.
        static let maxEntries = 50
        static let fallbackExtension = "sub"
        static let indexExtension = "idx"
        static let companionExtension = "sub"
    }

    static let shared = SubtitleFileCache()

    private let folder: URL
    private let session: URLSession
    private let publicationLock = NSLock()

    init(folder: URL? = nil, session: URLSession? = nil) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.folder = folder ?? caches.appending(path: Defaults.folderName, directoryHint: .isDirectory)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Defaults.requestTimeout
        self.session = session ?? URLSession(configuration: configuration)
        try? FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
        prune()
    }

    /// A VobSub index is usable only with its same-basename binary companion.
    func cachedFile(for url: URL) -> URL? {
        let file = localFile(for: url, in: entry(for: url))
        let files = isVobSub(url) ? [file, companion(of: file)] : [file]
        return files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) } ? file : nil
    }

    /// Publishes the complete entry only after every required download succeeds.
    func download(_ url: URL) async -> URL? {
        if let file = cachedFile(for: url) { return file }
        let staging = folder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        guard (try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: staging) }
        let file = localFile(for: url, in: staging)
        guard await fetch(url, to: file) else { return nil }
        if isVobSub(url), !(await fetch(companion(of: url), to: companion(of: file))) { return nil }
        guard !Task.isCancelled else { return nil }
        return publish(staging, for: url)
    }

    private func fetch(_ url: URL, to file: URL) async -> Bool {
        guard SecureTransport.permits(url),
              let (temporary, response) = try? await session.download(from: url, delegate: SecureRedirectDelegate.shared) else { return false }
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard HTTPStatus.success.contains((response as? HTTPURLResponse)?.statusCode ?? .zero) else { return false }
        return (try? FileManager.default.moveItem(at: temporary, to: file)) != nil
    }

    private func publish(_ staging: URL, for url: URL) -> URL? {
        publicationLock.withLock {
            // A concurrent request may already have installed the complete entry.
            if let file = cachedFile(for: url) { return file }
            let destination = entry(for: url)
            try? FileManager.default.removeItem(at: destination)
            guard (try? FileManager.default.moveItem(at: staging, to: destination)) != nil else { return nil }
            return cachedFile(for: url)
        }
    }

    private func entry(for url: URL) -> URL {
        let name = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appending(path: name, directoryHint: .isDirectory)
    }

    private func localFile(for url: URL, in directory: URL) -> URL {
        let ext = url.pathExtension.isEmpty ? Defaults.fallbackExtension : url.pathExtension.lowercased()
        return directory.appending(path: Defaults.fileName).appendingPathExtension(ext)
    }

    private func isVobSub(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == Defaults.indexExtension
    }

    private func companion(of url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension(Defaults.companionExtension)
    }

    private func prune() {
        let key = URLResourceKey.contentModificationDateKey
        guard let entries = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [key]),
              entries.count > Defaults.maxEntries
        else { return }
        let newestFirst = entries.sorted {
            let first = (try? $0.resourceValues(forKeys: [key]).contentModificationDate) ?? .distantPast
            let second = (try? $1.resourceValues(forKeys: [key]).contentModificationDate) ?? .distantPast
            return first > second
        }
        newestFirst.dropFirst(Defaults.maxEntries).forEach { try? FileManager.default.removeItem(at: $0) }
    }
}

private enum HTTPStatus {
    static let success = 200..<300
}
