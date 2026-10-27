import Foundation
import RetroGuideKit

/// Tells servers that report playback (Jellyfin) what's playing, in order and
/// without holding up tuning: the Apple app's `PlaybackReporting`. The app
/// sends the player's position with each event and a progress tick.
actor PlaybackReporter {
    private struct Session {
        let client: any MediaServerClient
        let item: MediaItem
        let request: StreamRequest
        let tracks: ItemTracks?
        var selection: TrackSelection?
        var started = false
        var paused = false
        var lastPosition: TimeInterval?

        mutating func report(_ event: PlaybackReport.Event, position: TimeInterval?) -> PlaybackReport {
            if let position, position.isFinite { lastPosition = position }
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
    private var pending: [Pending] = []
    private var announced = Set<String>()
    private var isDraining = false

    func prepare(client: any MediaServerClient, item: MediaItem, request: StreamRequest, tracks: ItemTracks?, selection: TrackSelection?) {
        end(position: nil)
        guard client.reportsPlayback else { return }
        session = Session(client: client, item: item, request: request, tracks: tracks, selection: selection)
    }

    func started(position: TimeInterval?) {
        guard var session, !session.started else { return }
        session.started = true
        let report = session.report(.started, position: position)
        self.session = session
        enqueue(report, client: session.client)
        progress(position: position)
    }

    func select(_ selection: TrackSelection) {
        session?.selection = selection
        progress(position: nil)
    }

    func pause(_ paused: Bool, position: TimeInterval?) {
        session?.paused = paused
        progress(position: position)
    }

    func progress(position: TimeInterval?) {
        guard var session, session.started else { return }
        let report = session.report(.progress, position: position)
        self.session = session
        enqueue(report, client: session.client)
    }

    func end(position: TimeInterval?) {
        guard var session else { return }
        self.session = nil
        guard session.started else { return }
        let id = session.request.sessionID
        if !announced.contains(id), pending.contains(where: { $0.report.request.sessionID == id && $0.report.event == .started }) {
            // Surfed away before the server heard about this session: omit the
            // whole pair rather than creating a backlog of obsolete playback.
            pending.removeAll { $0.report.request.sessionID == id }
        } else {
            enqueue(session.report(.stopped, position: position), client: session.client)
        }
    }

    private func enqueue(_ report: PlaybackReport, client: any MediaServerClient) {
        if report.event == .progress {
            pending.removeAll { $0.report.event == .progress && $0.report.request.sessionID == report.request.sessionID }
        }
        pending.append(Pending(client: client, report: report))
        guard !isDraining else { return }
        isDraining = true
        Task { await drain() }
    }

    private func drain() async {
        while !pending.isEmpty {
            let next = pending.removeFirst()
            let id = next.report.request.sessionID
            if next.report.event == .started { announced.insert(id) }
            _ = await next.client.reportPlayback(next.report)
            if next.report.event == .stopped { announced.remove(id) }
        }
        isDraining = false
    }
}
