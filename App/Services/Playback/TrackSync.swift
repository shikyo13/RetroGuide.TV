import Foundation
import Observation
import RetroGuideKit

/// Saves audio and subtitle choices to the media server in the background,
/// like PASTA: every episode a choice covers gets it as the account's own
/// track choice, so every app signed in to the account, on any device, plays
/// the same tracks.
@MainActor
@Observable
final class TrackSync {
    private enum Tuning {
        /// Episodes saved at once (each is a read and a write).
        static let concurrentSaves = 4
    }

    struct Progress: Equatable {
        let saved: Int
        let total: Int
    }

    /// Progress of the save in flight, if any.
    private(set) var progress: Progress?

    private struct Job {
        let items: [MediaItem]
        let rules: TrackRules
        let preferences: LanguagePreferences?
    }

    @ObservationIgnored private let clientProvider: (String) -> (any MediaServerClient)?
    @ObservationIgnored private var queue: [Job] = []
    @ObservationIgnored private var worker: Task<Void, Never>?

    init(clientProvider: @escaping (String) -> (any MediaServerClient)?) {
        self.clientProvider = clientProvider
    }

    /// Saves `rules` for everything `scope` covers around `item`.
    func save(_ rules: TrackRules, around item: MediaItem, scope: TrackScope, among items: [MediaItem], preferences: LanguagePreferences?) {
        let covered = TrackRules.items(in: scope, around: item, among: items)
        guard !covered.isEmpty else { return }
        queue.append(Job(items: covered, rules: rules, preferences: preferences))
        guard worker == nil else { return }
        worker = Task { [weak self] in
            await self?.drain()
        }
    }

    func cancelAll() {
        queue.removeAll()
        worker?.cancel()
        worker = nil
        progress = nil
    }

    private func drain() async {
        while !queue.isEmpty, !Task.isCancelled {
            await run(queue.removeFirst())
        }
        progress = nil
        worker = nil
    }

    private func run(_ job: Job) async {
        progress = Progress(saved: .zero, total: job.items.count)
        let clientProvider = clientProvider
        await withTaskGroup(of: Void.self) { group in
            var next = job.items.makeIterator()
            func enqueue() {
                guard let item = next.next(), let client = clientProvider(item.serverID) else { return }
                let rules = job.rules
                group.addTask {
                    _ = await client.saveTracks(for: item, preferences: job.preferences) { tracks, automatic in
                        // The viewer's choices over what the account picks on its own,
                        // so going back to automatic saves the account's defaults.
                        rules.selection(for: item, tracks: ItemTracks(audio: tracks.audio, subtitles: tracks.subtitles, selection: automatic))
                    }
                }
            }
            for _ in 0..<Tuning.concurrentSaves {
                enqueue()
            }
            while await group.next() != nil {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                progress = progress.map { Progress(saved: $0.saved + 1, total: $0.total) }
                enqueue()
            }
        }
    }
}
