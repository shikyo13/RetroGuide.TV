import Foundation

/// What the "What's On" widget shows: a handful of channels (the one watched
/// last first) and their programs for the next hours. The app saves it into
/// the app group's shared container whenever the channel or the lineup
/// changes; the widget reads it and rotates through the channels.
struct WhatsOnSnapshot: Codable, Sendable {
    struct Program: Codable, Sendable, Hashable {
        /// The show (or movie) name, and the episode line ("S2 E14 · Title", or the year).
        let title: String
        let episode: String?
        let start: Date
        let end: Date
        /// File names in ``WhatsOnStore/artworkFolder``: backdrop, title logo, episode still.
        let backdropFile: String?
        let logoFile: String?
        let stillFile: String?
    }

    struct Channel: Codable, Sendable, Hashable {
        let id: String
        let number: Int
        let name: String
        let callSign: String
        let programs: [Program]

        func program(at date: Date) -> Program? {
            programs.first { $0.start <= date && date < $0.end }
        }
    }

    let channels: [Channel]
    var pinned: Bool? = nil
    var updatedAt: Date? = nil

    /// Until when every channel has a schedule.
    var coveredUntil: Date? {
        channels.compactMap { $0.programs.last?.end }.min()
    }
}

/// Where the app and the widget share the snapshot, which channel the
/// viewer flipped the widget to, and how a widget tap names a channel.
enum WhatsOnStore {
    static let appGroup = "group.com.adamhunt.retroguide"
    static let widgetKind = "WhatsOnWidget"
    static let artworkFolder = "whats-on-artwork"
    private static let snapshotFile = "whats-on.json"
    private static let offsetKey = "whatsOnOffset"
    private static let urlScheme = "retroguide"
    private static let channelHost = "channel"
    private static let channelIDQuery = "id"

    static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    static func load(from directory: URL? = container) -> WhatsOnSnapshot? {
        guard let url = directory?.appending(path: snapshotFile), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WhatsOnSnapshot.self, from: data)
    }

    /// Saves `snapshot` with its artwork (file name to image data), replacing what was there.
    @discardableResult
    static func save(_ snapshot: WhatsOnSnapshot, artwork: [String: Data], in directory: URL? = container) -> Bool {
        guard let container = directory else { return false }
        let previousFiles = Set(load(from: container)?.channels.flatMap { $0.programs.flatMap { [$0.backdropFile, $0.logoFile, $0.stillFile].compactMap { $0 } } } ?? [])
        let currentFiles = Set(snapshot.channels.flatMap { $0.programs.flatMap { [$0.backdropFile, $0.logoFile, $0.stillFile].compactMap { $0 } } })
        let folder = container.appending(path: artworkFolder)
        guard saveArtwork(artwork, in: container) else { return false }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: container.appending(path: snapshotFile), options: .atomic)
            // Keep the previous snapshot's images during publication; bound storage to two snapshots.
            if let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                let retained = previousFiles.union(currentFiles)
                for file in files where !retained.contains(file.lastPathComponent) { try? FileManager.default.removeItem(at: file) }
            }
            return true
        } catch {
            return false
        }
    }

    /// Publish small batches without keeping the whole guide's image data in memory.
    static func saveArtwork(_ artwork: [String: Data], in directory: URL? = container) -> Bool {
        guard let container = directory else { return false }
        let folder = container.appending(path: artworkFolder)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, data) in artwork {
                try data.write(to: folder.appending(path: name), options: .atomic)
            }
            return true
        } catch {
            return false
        }
    }

    static func clear(in directory: URL? = container) {
        guard let container = directory else { return }
        try? FileManager.default.removeItem(at: container.appending(path: snapshotFile))
        try? FileManager.default.removeItem(at: container.appending(path: artworkFolder))
    }

    static func artworkURL(_ file: String?, in directory: URL? = container) -> URL? {
        guard let file else { return nil }
        return directory?.appending(path: artworkFolder).appending(path: file)
    }

    /// How many channels the viewer has flipped the widget on from its rotation.
    static var offset: Int {
        UserDefaults(suiteName: appGroup)?.integer(forKey: offsetKey) ?? .zero
    }

    static func flip(by step: Int) {
        UserDefaults(suiteName: appGroup)?.set(offset + step, forKey: offsetKey)
    }

    /// `retroguide://channel?id=<id>`: opens the app on that channel
    /// (ids can contain slashes, so they go in the query).
    static func url(forChannel id: String) -> URL? {
        var components = URLComponents()
        components.scheme = urlScheme
        components.host = channelHost
        components.queryItems = [URLQueryItem(name: channelIDQuery, value: id)]
        return components.url
    }

    static func channelID(from url: URL) -> String? {
        guard url.scheme == urlScheme, url.host == channelHost else { return nil }
        let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == channelIDQuery }?.value
        return id?.isEmpty == false ? id : nil
    }
}
