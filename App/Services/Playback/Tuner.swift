import Observation
import RetroGuideKit
import UIKit

/// The "cable box": knows which channel is on, joins programs mid-stream,
/// follows the schedule from program to program and supports channel surfing.
/// Actual decoding is delegated to a ``PlaybackEngine``.
@MainActor
@Observable
final class Tuner {
    enum Signal: Equatable {
        case off
        case tuning
        case live
        case intermission
        case noSignal(String)
    }

    private enum Timing {
        /// Wait this long after the last surf press before starting a stream,
        /// so flipping through channels never opens a stream per channel.
        static let surfSettle: Duration = .milliseconds(450)
        /// Retry quietly (behind the tuning static) with these back-off
        /// delays before showing No Signal.
        static let quickRetryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4)]
        /// After quick retries are exhausted, keep retrying at this interval.
        static let retryDelay: Duration = .seconds(15)
    }

    private(set) var channel: Channel?
    private(set) var program: ScheduledProgram?
    private(set) var signal: Signal = .off
    /// Increments on every tune so overlays can re-appear even on the same channel.
    private(set) var tuneGeneration = 0
    /// The playing video's dynamic range and frame rate. Kept while surfing
    /// until the next video reports its own, so the TV doesn't switch modes in between.
    private(set) var videoFormat: VideoFormat?
    private(set) var engine: any PlaybackEngine

    @ObservationIgnored var onChannelChanged: ((String) -> Void)?
    /// Called with a server id when its streams keep failing, so reachability can be re-checked.
    @ObservationIgnored var onServerTrouble: ((String) -> Void)?
    @ObservationIgnored var onVideoFormatChanged: (() -> Void)?

    @ObservationIgnored private var channels: [Channel] = []
    @ObservationIgnored private var previousChannelID: String?
    @ObservationIgnored private let clientProvider: (String) -> (any MediaServerClient)?
    @ObservationIgnored private var activeStream: ActiveStream?
    @ObservationIgnored private var tuneTask: Task<Void, Never>?
    @ObservationIgnored private var boundaryTask: Task<Void, Never>?
    @ObservationIgnored private var failedAttempts = 0

    private struct ActiveStream {
        let client: any MediaServerClient
        let sessionID: String
    }

    init(engineKind: PlaybackEngineKind, clientProvider: @escaping (String) -> (any MediaServerClient)?) {
        self.clientProvider = clientProvider
        self.engine = PlaybackEngineFactory.make(engineKind)
        attach(engine)
    }

    // MARK: - Engine

    /// Swaps the playback engine (from Settings) and rejoins the current channel.
    func useEngine(_ kind: PlaybackEngineKind) {
        guard kind != engine.kind else { return }
        stopPlayback()
        engine = PlaybackEngineFactory.make(kind)
        attach(engine)
        setVideoFormat(nil)
        resume()
    }

    private func attach(_ engine: any PlaybackEngine) {
        engine.onEvent = { [weak self] event in
            self?.handle(event)
        }
    }

    // MARK: - Lineup

    /// Updates the channels available for surfing, keeping the current channel if it still exists.
    func setChannels(_ channels: [Channel]) {
        self.channels = channels
        guard let current = channel else { return }
        if let updated = channels.first(where: { $0.id == current.id }) {
            channel = updated
        } else if let first = channels.first {
            tune(to: first)
        } else {
            powerOff()
        }
    }

    func channel(withID id: String?) -> Channel? {
        channels.first { $0.id == id }
    }

    // MARK: - Remote actions

    func tune(to channel: Channel, surfing: Bool = false) {
        if channel.id != self.channel?.id {
            previousChannelID = self.channel?.id
        }
        self.channel = channel
        program = channel.timeline.program(at: .now)
        signal = .tuning
        failedAttempts = .zero
        tuneGeneration += 1
        onChannelChanged?(channel.id)
        stopTimers()
        tuneTask = Task { [weak self] in
            if surfing {
                try? await Task.sleep(for: Timing.surfSettle)
            }
            guard !Task.isCancelled else { return }
            await self?.startPlayback()
        }
    }

    func channelUp() {
        step(by: 1)
    }

    func channelDown() {
        step(by: -1)
    }

    /// Jumps back to the previously watched channel (the remote's "Last" button).
    func recall() {
        guard let previous = channel(withID: previousChannelID) else { return }
        tune(to: previous)
    }

    // MARK: - Lifecycle

    /// Releases the stream while the app is in the background.
    func suspend() {
        stopPlayback()
        signal = .off
    }

    /// Rejoins the current channel live when returning to the foreground.
    func resume() {
        guard let channel else { return }
        tune(to: channel)
    }

    func powerOff() {
        suspend()
        channel = nil
        program = nil
    }

    // MARK: - Playback

    private func step(by offset: Int) {
        guard !channels.isEmpty else { return }
        let currentIndex = channels.firstIndex { $0.id == channel?.id } ?? .zero
        let nextIndex = (currentIndex + offset + channels.count) % channels.count
        tune(to: channels[nextIndex], surfing: true)
    }

    private func startPlayback() async {
        guard let channel, let program = channel.timeline.program(at: .now) else {
            signal = .noSignal("Nothing is scheduled on this channel.")
            return
        }
        self.program = program
        endActiveStream()

        let now = Date.now
        if program.isInIntermission(at: now) {
            enterIntermission(until: program.slotEnd)
            return
        }
        guard let client = clientProvider(program.item.serverID) else {
            signal = .noSignal("The server for this channel isn't connected.")
            return
        }
        // Every (re)start shows the tuning state until frames actually play.
        signal = .tuning
        let generation = tuneGeneration
        let tracks = await client.trackSelection(for: program.item)
        // The viewer may have changed channel while the selection was loading.
        guard generation == tuneGeneration, !Task.isCancelled else { return }
        do {
            let request = try client.streamRequest(
                for: program.item,
                startingAt: program.elapsed(at: now),
                capabilities: engine.capabilities
            )
            if request.needsTeardown {
                activeStream = ActiveStream(client: client, sessionID: request.sessionID)
            }
            engine.play(request, tracks: tracks)
            UIApplication.shared.isIdleTimerDisabled = true
            scheduleBoundary(at: program.contentEnd)
        } catch {
            fail(with: error.localizedDescription)
        }
    }

    private func handle(_ event: PlaybackEvent) {
        switch event {
        case .playing:
            guard signal == .tuning else { return }
            signal = .live
            failedAttempts = .zero
        case .ended:
            // The file ran shorter than its metadata; fill until the next program.
            if let program, signal == .live {
                enterIntermission(until: program.slotEnd)
            }
        case let .failed(message):
            guard signal == .tuning || signal == .live else { return }
            fail(with: message)
        case let .format(format):
            setVideoFormat(format)
        }
    }

    private func setVideoFormat(_ format: VideoFormat?) {
        guard format != videoFormat else { return }
        videoFormat = format
        onVideoFormatChanged?()
    }

    private func enterIntermission(until date: Date) {
        engine.stop()
        endActiveStream()
        signal = .intermission
        scheduleBoundary(at: date)
    }

    /// Sleeps until `date`, then follows the schedule (intermission or next program).
    private func scheduleBoundary(at date: Date) {
        boundaryTask?.cancel()
        boundaryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(date.timeIntervalSinceNow, .zero)))
            guard !Task.isCancelled, let self else { return }
            if let program, program.isInIntermission(at: .now) {
                enterIntermission(until: program.slotEnd)
            } else {
                signal = .tuning
                await startPlayback()
            }
        }
    }

    private func fail(with message: String) {
        engine.stop()
        endActiveStream()
        boundaryTask?.cancel()
        let delay: Duration
        if Timing.quickRetryDelays.indices.contains(failedAttempts) {
            delay = Timing.quickRetryDelays[failedAttempts]
            signal = .tuning
        } else {
            delay = Timing.retryDelay
            signal = .noSignal(message)
            if let serverID = program?.item.serverID {
                onServerTrouble?(serverID)
            }
        }
        failedAttempts += 1
        boundaryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.startPlayback()
        }
    }

    private func stopPlayback() {
        stopTimers()
        engine.stop()
        endActiveStream()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func stopTimers() {
        tuneTask?.cancel()
        boundaryTask?.cancel()
    }

    /// Tells the server to release a repackaged stream.
    private func endActiveStream() {
        guard let stream = activeStream else { return }
        activeStream = nil
        Task.detached(priority: .utility) {
            await stream.client.endStream(sessionID: stream.sessionID)
        }
    }
}
