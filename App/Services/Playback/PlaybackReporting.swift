import Foundation
import RetroGuideKit

/// Sends ordered session updates without holding up tuning or track changes.
@MainActor
final class PlaybackReporting {
    private enum Timing {
        static let progressInterval: Duration = .seconds(10)
    }

    private struct Session {
        let client: any MediaServerClient
        let item: MediaItem
        let request: StreamRequest
        let tracks: ItemTracks?
        var selection: TrackSelection?
        let position: () -> TimeInterval?
        var started = false
        var paused = false
        var lastPosition: TimeInterval?

        mutating func report(_ event: PlaybackReport.Event) -> PlaybackReport {
            if let value = position(), value.isFinite { lastPosition = value }
            return PlaybackReport(event: event, item: item, request: request,
                position: lastPosition ?? request.startPosition, isPaused: paused,
                tracks: tracks, selection: selection)
        }
    }

    private struct Pending {
        let client: any MediaServerClient
        let report: PlaybackReport
    }

    private var session: Session?
    private var timer: Task<Void, Never>?
    private var pending: [Pending] = []
    private var announced = Set<String>()
    private var worker: Task<Void, Never>?

    func prepare(client: any MediaServerClient, item: MediaItem, request: StreamRequest,
                 tracks: ItemTracks?, selection: TrackSelection?, position: @escaping () -> TimeInterval?) {
        end()
        guard client.reportsPlayback else { return }
        session = Session(client: client, item: item, request: request, tracks: tracks, selection: selection, position: position)
    }

    func started() {
        guard var session, !session.started else { return }
        session.started = true
        let report = session.report(.started)
        self.session = session
        enqueue(report, client: session.client)
        progress()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: Timing.progressInterval) } catch { return }
                self?.progress()
            }
        }
    }

    func select(_ selection: TrackSelection) {
        session?.selection = selection
        progress()
    }

    func pause(_ paused: Bool) {
        session?.paused = paused
        progress()
    }

    func end() {
        timer?.cancel()
        timer = nil
        guard var session else { return }
        self.session = nil
        guard session.started else { return }
        let id = session.request.sessionID
        if !announced.contains(id), pending.contains(where: { $0.report.request.sessionID == id && $0.report.event == .started }) {
            // Surfed away before the server heard about this session: omit the
            // whole pair rather than creating a backlog of obsolete playback.
            pending.removeAll { $0.report.request.sessionID == id }
        } else {
            enqueue(session.report(.stopped), client: session.client)
        }
    }

    private func progress() {
        guard var session, session.started else { return }
        let report = session.report(.progress)
        self.session = session
        enqueue(report, client: session.client)
    }

    private func enqueue(_ report: PlaybackReport, client: any MediaServerClient) {
        if report.event == .progress {
            pending.removeAll { $0.report.event == .progress && $0.report.request.sessionID == report.request.sessionID }
        }
        pending.append(Pending(client: client, report: report))
        guard worker == nil else { return }
        worker = Task { [weak self] in await self?.drain() }
    }

    private func drain() async {
        while !pending.isEmpty {
            let next = pending.removeFirst()
            let id = next.report.request.sessionID
            if next.report.event == .started { announced.insert(id) }
            _ = await next.client.reportPlayback(next.report)
            if next.report.event == .stopped { announced.remove(id) }
        }
        worker = nil
    }

    isolated deinit { timer?.cancel() }
}
