import Foundation
import RetroGuideKit

/// Owns the player only during a scheduled break. Its deadline never waits for a server.
@MainActor
final class CommercialPlayback {
    private let engine: any PlaybackEngine
    private let clientProvider: (String) -> (any MediaServerClient)?
    private let allows: (MediaItem) -> Bool
    private let onPlaying: () -> Void
    private let onCard: () -> Void
    private let onFinished: () -> Void
    private let onFormat: (VideoFormat) -> Void
    private var plan: CommercialBreakPlan?
    private var generation = 0
    private var work: Task<Void, Never>?
    private var boundary: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var stream: (any MediaServerClient, StreamRequest)?
    private var clip: CommercialBreakPlan.Clip?
    private var isCancelled = false
    private(set) var item: MediaItem?

    init(engine: any PlaybackEngine, clientProvider: @escaping (String) -> (any MediaServerClient)?, allows: @escaping (MediaItem) -> Bool,
         onPlaying: @escaping () -> Void, onCard: @escaping () -> Void, onFinished: @escaping () -> Void, onFormat: @escaping (VideoFormat) -> Void) {
        self.engine = engine; self.clientProvider = clientProvider; self.allows = allows
        self.onPlaying = onPlaying; self.onCard = onCard; self.onFinished = onFinished; self.onFormat = onFormat
    }
    func start(_ plan: CommercialBreakPlan) {
        self.plan = plan
        deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(plan.end.timeIntervalSinceNow, .zero)))
            guard !Task.isCancelled, let self, !isCancelled else { return }
            cancel()
            onFinished()
        }
        advance()
    }
    func cancel() {
        isCancelled = true
        deadline?.cancel(); deadline = nil
        boundary?.cancel(); boundary = nil
        stopClip()
        plan = nil
    }
    func handle(_ event: PlaybackEvent) {
        guard !isCancelled else { return }
        switch event {
        case .playing:
            guard let item, allows(item), let clip, Date.now < clip.end else { showCard(); return }
            onPlaying()
        case .ended:
            // Metadata can be slightly longer than the file. Keep the next clip's time.
            stopClip()
            onCard()
        case .failed:
            showCard()
        case .format(let format): onFormat(format)
        }
    }
    func enforceAccess() {
        if let item, !allows(item) { showCard() }
    }
    private func advance() {
        guard !isCancelled, let plan else { return }
        stopClip()
        guard let clip = plan.clip(at: .now), allows(clip.item), let client = clientProvider(clip.item.serverID) else {
            onCard()
            return
        }
        self.clip = clip
        item = clip.item
        let token = generation
        boundary = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(clip.end.timeIntervalSinceNow, .zero)))
            guard !Task.isCancelled, let self, !isCancelled else { return }
            advance()
        }
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let prepared = try await client.preparePlayback(for: clip.item, startingAt: clip.position(at: .now), capabilities: engine.capabilities, preferences: nil)
                var request = prepared.request
                guard isCurrent(token, clip: clip) else { release(client, request); return }
                // Server-positioned streams cannot be sought client-side. Skip a stale
                // preparation rather than start an ad behind the channel's clock.
                if request.startsAtPosition && clip.position(at: .now) - request.startPosition >= Timing.positionTolerance {
                    release(client, request)
                    request = try await client.streamRequest(for: clip.item, startingAt: clip.position(at: .now), capabilities: engine.capabilities)
                    guard isCurrent(token, clip: clip) else { release(client, request); return }
                    guard clip.position(at: .now) - request.startPosition < Timing.positionTolerance else {
                        release(client, request); showCard(); return
                    }
                }
                stream = (client, request)
                engine.setSubtitleDelay(.zero)
                engine.play(request.starting(at: clip.position(at: .now)), tracks: nil)
            } catch {
                guard isCurrent(token, clip: clip) else { return }
                showCard()
            }
        }
    }
    private enum Timing { static let positionTolerance: TimeInterval = 1 }
    private func isCurrent(_ token: Int, clip: CommercialBreakPlan.Clip) -> Bool {
        !Task.isCancelled && !isCancelled && generation == token && Date.now < clip.end && allows(clip.item)
    }
    private func showCard() {
        boundary?.cancel(); boundary = nil
        stopClip()
        onCard()
    }
    private func stopClip() {
        generation += 1
        work?.cancel(); work = nil
        item = nil; clip = nil
        if let (client, request) = stream { release(client, request); stream = nil }
        engine.stop()
    }
    private func release(_ client: any MediaServerClient, _ request: StreamRequest) {
        guard request.needsTeardown else { return }
        Task { await client.endStream(sessionID: request.sessionID) }
    }
}
