import Foundation

/// Where the library's bundled data files (channel catalog, genre taxonomy,
/// title classification) are read from.
///
/// On Apple platforms they're found in the package's resource bundle. An
/// Android app has no such bundle next to it, so it copies the files out of
/// its own assets and names that folder here before using the library.
public enum KitResources {
    nonisolated(unsafe) private static var overrideDirectory: URL?
    private static let lock = NSLock()

    /// Reads resources from `directory` instead of the package's bundle.
    public static func use(directory: URL) {
        lock.withLock { overrideDirectory = directory }
    }

    static func url(forResource name: String, withExtension fileExtension: String) -> URL? {
        if let directory = lock.withLock({ overrideDirectory }) {
            return directory.appending(path: "\(name).\(fileExtension)")
        }
        return Bundle.module.url(forResource: name, withExtension: fileExtension)
    }
}
