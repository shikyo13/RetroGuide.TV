import Foundation
import RetroGuideKit

/// Caches library snapshots on disk so the guide is ready instantly at launch.
///
/// Snapshots live in the Caches directory: tvOS may purge it, in which case the
/// app simply re-indexes the library. Channel schedules are unaffected because
/// they are derived deterministically from the content.
struct LibrarySnapshotStore: Sendable {
    private let directory: URL

    init(directory: URL? = nil) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.directory = directory ?? caches.appendingPathComponent(AppIdentity.cacheFolderName, isDirectory: true)
    }

    func load(serverID: String) async -> LibrarySnapshot? {
        let url = fileURL(for: serverID)
        return await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url),
                  let snapshot = try? PropertyListDecoder().decode(LibrarySnapshot.self, from: data),
                  snapshot.isCurrentFormat
            else { return nil }
            return snapshot
        }.value
    }

    func save(_ snapshot: LibrarySnapshot) async {
        let directory = directory
        let url = fileURL(for: snapshot.serverID)
        await Task.detached(priority: .utility) {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            guard let data = try? encoder.encode(snapshot) else { return }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }.value
    }

    func remove(serverID: String) {
        try? FileManager.default.removeItem(at: fileURL(for: serverID))
    }

    private func fileURL(for serverID: String) -> URL {
        let safeName = serverID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? serverID
        return directory.appendingPathComponent("library-\(safeName).plist")
    }
}
