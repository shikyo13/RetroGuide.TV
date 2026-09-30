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
        let failed: Int
        let total: Int

        var done: Int { saved + failed }
    }

    /// Progress of the save in flight, if any.
    private(set) var progress: Progress?
    /// Episodes whose choice couldn't be saved (server unreachable, write
    /// refused), kept until ``retryFailed()`` or the next save.
    private(set) var failedCount = 0
    @ObservationIgnored private var failedJobs: [Job] = []

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
        enqueue(Job(items: covered, rules: rules, preferences: preferences))
    }

    /// Tries the episodes that failed to save again.
    func retryFailed() {
        let jobs = failedJobs
        failedJobs = []
        failedCount = .zero
        jobs.forEach(enqueue)
    }

    private func enqueue(_ job: Job) {
        queue.append(job)
        guard worker == nil else { return }
        worker = Task { [weak self] in
            await self?.drain()
        }
    }

    func cancelAll() {
        queue.removeAll()
        failedJobs = []
        failedCount = .zero
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
        progress = Progress(saved: .zero, failed: .zero, total: job.items.count)
        let clientProvider = clientProvider
        var failedItems: [MediaItem] = []
        await withTaskGroup(of: (MediaItem, Bool).self) { group in
            var next = job.items.makeIterator()
            func enqueue() {
                guard let item = next.next() else { return }
                let rules = job.rules
                let client = clientProvider(item.serverID)
                group.addTask {
                    // A server that isn't connected can't save anything.
                    guard let client else { return (item, false) }
                    let saved = await client.saveTracks(for: item, preferences: job.preferences) { tracks, automatic in
                        // The viewer's choices over what the account picks on its own,
                        // so going back to automatic saves the account's defaults.
                        rules.selection(for: item, tracks: ItemTracks(audio: tracks.audio, subtitles: tracks.subtitles, selection: automatic))
                    }
                    return (item, saved)
                }
            }
            for _ in 0..<Tuning.concurrentSaves {
                enqueue()
            }
            while let (item, saved) = await group.next() {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                if !saved {
                    failedItems.append(item)
                }
                progress = progress.map { Progress(saved: $0.saved + (saved ? 1 : 0), failed: $0.failed + (saved ? 0 : 1), total: $0.total) }
                enqueue()
            }
        }
        if !failedItems.isEmpty {
            failedJobs.append(Job(items: failedItems, rules: job.rules, preferences: job.preferences))
            failedCount += failedItems.count
        }
    }
}
