import Foundation

/// Serializes file publication, including sign-out, so cancelled artwork work cannot revive an old snapshot.
actor SnapshotFileWriter {
    private var latestGeneration = 0
    private let directory: URL?

    init(directory: URL? = WhatsOnStore.container) {
        self.directory = directory
    }

    func missingArtwork(_ names: [String]) -> Set<String> {
        Set(names.filter { name in
            guard let url = WhatsOnStore.artworkURL(name, in: directory),
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return true }
            return size == 0
        })
    }

    func saveArtwork(_ artwork: [String: Data], generation: Int) -> Bool {
        guard generation >= latestGeneration else { return false }
        latestGeneration = generation
        return WhatsOnStore.saveArtwork(artwork, in: directory)
    }

    func save(_ snapshot: WhatsOnSnapshot, artwork: [String: Data], generation: Int) -> Bool {
        guard generation >= latestGeneration else { return false }
        latestGeneration = generation
        return WhatsOnStore.save(snapshot, artwork: artwork, in: directory)
    }

    func clear(generation: Int) {
        guard generation >= latestGeneration else { return }
        latestGeneration = generation
        WhatsOnStore.clear(in: directory)
    }
}
