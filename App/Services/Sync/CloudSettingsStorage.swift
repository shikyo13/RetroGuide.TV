import Foundation

/// The journal is larger than ordinary preferences. tvOS terminates apps whose
/// UserDefaults exceed its limit, so only small switches live there.
@MainActor
struct CloudSettingsStorage {
    enum Failure: Error { case tooLarge }
    private static let maximumBytes = 64 * 1_024 * 1_024
    let directory: URL

    init(directory: URL? = nil) {
        if let directory { self.directory = directory; return }
        #if os(tvOS)
        let location = FileManager.SearchPathDirectory.cachesDirectory
        #else
        let location = FileManager.SearchPathDirectory.applicationSupportDirectory
        #endif
        self.directory = FileManager.default.urls(for: location, in: .userDomainMask)[0]
            .appendingPathComponent("SettingsSync", isDirectory: true)
    }

    func load() throws -> CloudSettingsState? {
        let url = directory.appendingPathComponent("journal.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= Self.maximumBytes else { throw Failure.tooLarge }
        return try JSONDecoder().decode(CloudSettingsState.self, from: Data(contentsOf: url))
    }

    func save(_ state: CloudSettingsState, name: String = "journal") throws {
        let data = try JSONEncoder().encode(state)
        guard data.count <= Self.maximumBytes else { throw Failure.tooLarge }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name + ".json"), options: .atomic)
    }

    func preserveUnreadableJournal() throws {
        let original = directory.appendingPathComponent("journal.json")
        let preserved = directory.appendingPathComponent("unreadable-journal.json")
        if FileManager.default.fileExists(atPath: preserved.path) { try FileManager.default.removeItem(at: preserved) }
        if FileManager.default.fileExists(atPath: original.path) { try FileManager.default.moveItem(at: original, to: preserved) }
    }
}
