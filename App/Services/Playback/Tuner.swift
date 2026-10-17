import Observation
import OSLog
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
        /// While flipping through channels, wait this long after each press
        /// before starting a stream, so flipping never opens one per channel.
        static let surfSettle: Duration = .milliseconds(450)
        /// Presses closer together than this count as flipping; a single
        /// press starts its stream right away.
        static let flippingWindow: Duration = .seconds(1)
        /// Retry quietly (behind the tuning static) with these back-off
        /// delays before showing No Signal.
        static let quickRetryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4)]
        /// A stream the server starts at a position (Apple player, remuxed)
        /// can only start on whole seconds; if preparing it put it this far
        /// behind, it's requested again at the current position.
        static let serverPositionTolerance: TimeInterval = 1
        /// After quick retries are exhausted, keep retrying at this interval.
        static let retryDelay: Duration = .seconds(15)
        /// A program not playing this long after its stream was opened won't
        /// start (typically a file with missing data, which the player would
        /// otherwise read for minutes): the channel moves on at the next program.
        static let startTimeout: Duration = .seconds(30)
    }

    private enum Message {
        static let didNotStart = "This program won't start. Its file may be damaged."
    }

    private(set) var channel: Channel?
    private(set) var program: ScheduledProgram?
    private(set) var signal: Signal = .off {
        didSet {
            if signal != oldValue {
                onSignalChanged?()
                #if os(iOS)
                // Picture in Picture may start by itself only while a channel plays.
                if signal == .live, pictureInPicture == nil {
                    setUpPictureInPicture()
                }
                pictureInPicture?.playbackStateChanged(isPlaying: signal == .live)
                #endif
            }
        }
    }
    /// Increments on every tune so overlays can re-appear even on the same channel.
    private(set) var tuneGeneration = 0
    /// The tune the engine's current stream was started for.
    @ObservationIgnored private var playbackGeneration: Int?
    /// Channel changes the viewer made (not automatic retunes after a lineup
    /// rebuild), so a pending "return to the last channel" knows whether the
    /// viewer has moved on.
    private(set) var viewerTuneCount = 0
    /// The playing video's dynamic range and frame rate. Kept while surfing
    /// until the next video reports its own, so the TV doesn't switch modes in between.
    private(set) var videoFormat: VideoFormat?
    private(set) var engine: any PlaybackEngine

    @ObservationIgnored var onChannelChanged: ((String) -> Void)?
    /// Called with a server id when its streams keep failing, so reachability can be re-checked.
    @ObservationIgnored var onServerTrouble: ((String) -> Void)?
    @ObservationIgnored var onVideoFormatChanged: (() -> Void)?
    /// Called when the Picture in Picture window is closed (not returned to the app from).
    @ObservationIgnored var onPictureInPictureClosed: (() -> Void)?
    #if os(iOS)
    @ObservationIgnored private var pictureInPicture: PictureInPictureController?
    #endif
    /// Called whenever ``signal`` changes (tuning, live, off…).
    @ObservationIgnored var onSignalChanged: (() -> Void)?
    /// The viewer's account language settings, for items they haven't chosen tracks for.
    @ObservationIgnored var languagePreferences: LanguagePreferences?
    /// The tuned program's audio and subtitle tracks (when the server says),
    /// and the ones playing.
    private(set) var currentTracks: ItemTracks?
    private(set) var currentSelection: TrackSelection?
    /// How far subtitles are moved for what's on now (see ``SubtitleTiming``).
    private(set) var subtitleDelay: TimeInterval = .zero
    /// The item ``subtitleDelay`` was set for: a new program starts in sync.
    @ObservationIgnored private var subtitleDelayItemID: String?
    /// The viewer's audio and subtitle choices, each at its own scope.
    private(set) var trackRules = TrackRules()
    /// Called after the viewer changes a choice: the new rules, the item it
    /// was made on, and how far the change reaches (to save it to the server).
    @ObservationIgnored var onTrackRulesChanged: ((TrackRules, MediaItem, TrackScope) -> Void)?

    @ObservationIgnored private var channels: [Channel] = []
    @ObservationIgnored private var previousChannelID: String?
    @ObservationIgnored private let clientProvider: (String) -> (any MediaServerClient)?
    @ObservationIgnored private var activeStream: ActiveStream?
    @ObservationIgnored private var tuneTask: Task<Void, Never>?
    @ObservationIgnored private var boundaryTask: Task<Void, Never>?
    @ObservationIgnored private var startWatchdog: Task<Void, Never>?
    @ObservationIgnored private var failedAttempts = 0
    /// When the viewer last flipped a channel (see ``Timing/flippingWindow``).
    @ObservationIgnored private var lastSurf: ContinuousClock.Instant?
    /// When the current tune started, for the time-to-picture log.
    @ObservationIgnored private var tuneStart: ContinuousClock.Instant?
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "tuner")

    private struct ActiveStream {
        let client: any MediaServerClient
        let sessionID: String
    }

    init(engineKind: PlaybackEngineKind, clientProvider: @escaping (String) -> (any MediaServerClient)?) {
        self.clientProvider = clientProvider
        self.engine = PlaybackEngineFactory.make(engineKind)
        attach(engine)
    }

    /// Closes the Picture in Picture window (the viewer is back in the app).
    func closePictureInPicture() {
        #if os(iOS)
        guard pictureInPicture?.isActive == true else { return }
        pictureInPicture?.stop()
        #endif
    }

    /// Whether the channel is showing in the Picture in Picture window.
    var isPictureInPictureActive: Bool {
        #if os(iOS)
        pictureInPicture?.isActive ?? false
        #else
        false
        #endif
    }

    // MARK: - Engine

    /// Swaps the playback engine (from Settings) and rejoins the current channel.
    func useEngine(_ kind: PlaybackEngineKind) {
        guard kind != engine.kind else { return }
        suspend()
        engine = PlaybackEngineFactory.make(kind)
        attach(engine)
        setVideoFormat(nil)
        resume()
    }

    private func attach(_ engine: any PlaybackEngine) {
        engine.onEvent = { [weak self] event in
            self?.handle(event)
        }
        #if os(iOS)
        // Made once the new player shows a channel (see ``setUpPictureInPicture()``).
        pictureInPicture?.stop()
        pictureInPicture = nil
        #endif
    }

    #if os(iOS)
    /// Picture in Picture for the current player. Made once a channel is on
    /// screen: iOS only starts it by itself for a source that was showing
    /// when the controller was made.
    private func setUpPictureInPicture() {
        let engine = engine
        let pictureInPicture = PictureInPictureController(engine: engine)
        pictureInPicture?.onChangeChannel = { [weak self] direction in
            if direction > .zero {
                self?.channelUp()
            } else {
                self?.channelDown()
            }
        }
        pictureInPicture?.onSetPlaying = { [weak self] playing in
            if playing {
                self?.continueStream()
            } else {
                self?.pauseStream()
            }
        }
        pictureInPicture?.onActiveChanged = { [weak engine] active in
            engine?.setPictureInPictureActive(active)
        }
        pictureInPicture?.onClose = { [weak self] in
            self?.onPictureInPictureClosed?()
        }
        self.pictureInPicture = pictureInPicture
    }
    #endif

    // MARK: - Lineup

    /// Updates the channels available for surfing, keeping the current channel if it still exists.
    func setChannels(_ channels: [Channel]) {
        self.channels = channels
        guard let current = channel else { return }
        if let updated = channels.first(where: { $0.id == current.id }) {
            channel = updated
            refreshProgram(on: updated)
        } else if let first = channels.first {
            tune(to: first, isAutomatic: true)
        } else {
            powerOff()
        }
    }

    /// A rebuilt lineup can change what's on: rejoin live if the program
    /// changed, or follow its new end if only that moved. While suspended the
    /// next ``resume()`` tunes in anyway.
    private func refreshProgram(on channel: Channel) {
        let airing = channel.timeline.program(at: .now)
        let previous = program
        program = airing
        guard signal != .off, let previous, let airing else { return }
        if airing.item.id != previous.item.id || airing.start != previous.start {
            tune(to: channel, isAutomatic: true)
        } else if airing.contentEnd != previous.contentEnd || airing.slotEnd != previous.slotEnd {
            scheduleBoundary(at: signal == .intermission ? airing.slotEnd : airing.contentEnd)
        }
    }

    /// The channel with `id`, including ids it had in earlier versions.
    func channel(withID id: String?) -> Channel? {
        guard let id else { return nil }
        return channels.first { $0.isIdentified(by: id) }
    }

    // MARK: - Audio and subtitles

    /// Shows subtitles `delay` seconds later (earlier when negative) for what's on now.
    func setSubtitleDelay(_ delay: TimeInterval) {
        subtitleDelay = SubtitleTiming.clamped(delay)
        engine.setSubtitleDelay(subtitleDelay)
    }

    /// Whether the viewer can pick tracks for what's playing right now.
    var canChooseTracks: Bool {
        engine.switchesTracksLive && currentTracks != nil
    }

    /// The scope of the audio choice covering what's on (`nil`: automatic).
    var audioScope: TrackScope? {
        program.flatMap { trackRules.audioRule(for: $0.item)?.scope }
    }

    /// The scope of the subtitle choice covering what's on (`nil`: automatic).
    var subtitleScope: TrackScope? {
        program.flatMap { trackRules.subtitleRule(for: $0.item)?.scope }
    }

    /// Takes rules that changed elsewhere (another device) and applies them to what's on.
    func replaceTrackRules(_ rules: TrackRules) {
        trackRules = rules
        guard let program, let tracks = currentTracks else { return }
        apply(rules.selection(for: program.item, tracks: tracks))
    }

    /// Plays `option` now and remembers it for everything `scope` covers.
    func chooseAudio(_ option: TrackOption, scope: TrackScope) {
        updateRules(scope: scope) { $0.setAudio(AudioRule(option), scope: scope, for: $1) }
    }

    /// Shows `option` (`nil`: subtitles off) now and remembers it for everything `scope` covers.
    func chooseSubtitles(_ option: TrackOption?, scope: TrackScope) {
        updateRules(scope: scope) { $0.setSubtitles(SubtitleRule(option), scope: scope, for: $1) }
    }

    /// Goes back to the server's and account's audio for this show.
    func resetAudio() {
        updateRules(scope: .show) { $0.resetAudio(for: $1) }
    }

    /// Goes back to the server's and account's subtitles for this show.
    func resetSubtitles() {
        updateRules(scope: .show) { $0.resetSubtitles(for: $1) }
    }

    private func updateRules(scope: TrackScope, _ change: (inout TrackRules, MediaItem) -> Void) {
        guard let program, let tracks = currentTracks else { return }
        change(&trackRules, program.item)
        onTrackRulesChanged?(trackRules, program.item, scope)
        apply(trackRules.selection(for: program.item, tracks: tracks))
    }

    private func apply(_ selection: TrackSelection) {
        currentSelection = selection
        engine.selectTracks(selection)
    }

    /// The viewer's choices where they made any, otherwise the server's.
    private func resolvedSelection(for program: ScheduledProgram, tracks: ItemTracks) -> TrackSelection {
        trackRules.selection(for: program.item, tracks: tracks)
    }

    // MARK: - Remote actions

    /// `isAutomatic`: the app retuned (a rebuilt lineup, a reconnected server),
    /// not the viewer.
    func tune(to channel: Channel, surfing: Bool = false, isAutomatic: Bool = false) {
        // Choosing the channel that's already on (the guide's picture, its
        // Watch button) keeps the stream; only a dead signal is worth a retry.
        if !isAutomatic, channel.id == self.channel?.id, isReceiving {
            return
        }
        if channel.id != self.channel?.id {
            previousChannelID = self.channel?.id
        }
        if !isAutomatic {
            viewerTuneCount += 1
        }
        self.channel = channel
        program = channel.timeline.program(at: .now)
        currentTracks = nil
        currentSelection = nil
        signal = .tuning
        failedAttempts = .zero
        tuneGeneration += 1
        onChannelChanged?(channel.id)
        stopTimers()
        // The old stream stops now rather than downloading while the new
        // one is prepared.
        engine.stop()
        endActiveStream()
        let now = ContinuousClock.now
        tuneStart = now
        logger.notice("tune \(channel.number, privacy: .public)\(isAutomatic ? " (automatic)" : "", privacy: .public)")
        let isFlipping = surfing && lastSurf.map { now - $0 < Timing.flippingWindow } == true
        lastSurf = surfing ? now : nil
        tuneTask = Task { [weak self] in
            if isFlipping {
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

    /// Holds the stream where it is while the app is briefly in the background
    /// (the app may keep running there, but its picture can't be drawn).
    func pauseStream() {
        guard isReceiving else { return }
        engine.setPaused(true)
        #if os(iOS)
        pictureInPicture?.playbackStateChanged(isPlaying: false)
        #endif
    }

    /// Continues a paused stream from where it stopped.
    func continueStream() {
        guard isReceiving else { return }
        engine.setPaused(false)
        #if os(iOS)
        pictureInPicture?.playbackStateChanged(isPlaying: signal == .live)
        #endif
    }

    /// Releases the stream while the app is in the background.
    func suspend() {
        stopPlayback()
        signal = .off
    }

    /// Rejoins the current channel live after ``suspend()``. Does nothing
    /// while the channel is still on (the app only went inactive, for
    /// Control Center or the app switcher), so the stream keeps playing.
    func resume() {
        guard let channel, signal == .off else { return }
        tune(to: channel, isAutomatic: true)
    }

    /// The channel is playing, starting or between programs: there's a
    /// stream (or a scheduled one) worth keeping.
    private var isReceiving: Bool {
        switch signal {
        case .tuning, .live, .intermission: true
        case .off, .noSignal: false
        }
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
        currentTracks = nil
        currentSelection = nil
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
        do {
            // With a single copy the tracks don't depend on the server's
            // decision, so both requests go out at once.
            let item = program.item
            let preferences = languagePreferences
            let hasOneCopy = item.versions.count <= 1
            async let singleCopyTracks = hasOneCopy ? client.tracks(for: item, version: nil, preferences: preferences) : nil
            var request = try await client.streamRequest(
                for: item,
                startingAt: program.elapsed(at: now),
                capabilities: engine.capabilities
            )
            // The tracks of the copy actually being streamed.
            let tracks = hasOneCopy
                ? await singleCopyTracks
                : await client.tracks(for: item, version: request.versionIndex, preferences: preferences)
            // A newer tune started while the stream was being prepared.
            guard generation == tuneGeneration, !Task.isCancelled else {
                if request.needsTeardown {
                    Task { await client.endStream(sessionID: request.sessionID) }
                }
                return
            }
            if request.needsTeardown {
                activeStream = ActiveStream(client: client, sessionID: request.sessionID)
            }
            // Preparing took time: join where the program is now, or move on
            // if it has ended meanwhile.
            let joinedAt = Date.now
            guard program.contains(joinedAt), !program.isInIntermission(at: joinedAt) else {
                endActiveStream()
                await startPlayback()
                return
            }
            if request.startsAtPosition, program.elapsed(at: joinedAt) - request.startPosition >= Timing.serverPositionTolerance {
                endActiveStream()
                request = try await client.streamRequest(for: program.item, startingAt: program.elapsed(at: .now), capabilities: engine.capabilities)
                guard generation == tuneGeneration, !Task.isCancelled else {
                    if request.needsTeardown {
                        Task { await client.endStream(sessionID: request.sessionID) }
                    }
                    return
                }
                if request.needsTeardown {
                    activeStream = ActiveStream(client: client, sessionID: request.sessionID)
                }
            }
            let selection = tracks.map { resolvedSelection(for: program, tracks: $0) }
            currentTracks = tracks
            currentSelection = selection
            playbackGeneration = generation
            if subtitleDelayItemID != program.item.id {
                subtitleDelayItemID = program.item.id
                subtitleDelay = .zero
            }
            engine.setSubtitleDelay(subtitleDelay)
            if let tuneStart {
                logger.notice("stream ready in \((ContinuousClock.now - tuneStart).milliseconds, privacy: .public) ms (\(String(describing: request.method), privacy: .public))")
            }
            engine.play(request.starting(at: program.elapsed(at: joinedAt)), tracks: selection)
            UIApplication.shared.isIdleTimerDisabled = true
            scheduleBoundary(at: program.contentEnd)
            watchStart(of: program, generation: generation)
        } catch {
            guard generation == tuneGeneration, !Task.isCancelled else { return }
            fail(with: error.localizedDescription)
        }
    }

    private func handle(_ event: PlaybackEvent) {
        // Events from a stream started for an earlier tune (the viewer changed
        // channel before it reported) don't describe what's tuned now.
        guard playbackGeneration == tuneGeneration else { return }
        switch event {
        case .playing:
            guard signal == .tuning else { return }
            startWatchdog?.cancel()
            if let tuneStart {
                logger.notice("live in \((ContinuousClock.now - tuneStart).milliseconds, privacy: .public) ms")
                self.tuneStart = nil
            }
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

    /// Gives up on a program that hasn't started after ``Timing/startTimeout``
    /// and waits for the next one, rather than retrying the same file.
    private func watchStart(of program: ScheduledProgram, generation: Int) {
        startWatchdog?.cancel()
        startWatchdog = Task { [weak self] in
            try? await Task.sleep(for: Timing.startTimeout)
            guard !Task.isCancelled, let self, generation == tuneGeneration, signal == .tuning else { return }
            engine.stop()
            endActiveStream()
            signal = .noSignal(Message.didNotStart)
            scheduleBoundary(at: program.slotEnd)
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
        startWatchdog?.cancel()
        engine.stop()
        endActiveStream()
        boundaryTask?.cancel()
        let delay: Duration
        let isQuickRetry = Timing.quickRetryDelays.indices.contains(failedAttempts)
        if isQuickRetry {
            delay = Timing.quickRetryDelays[failedAttempts]
            signal = .tuning
        } else {
            delay = Timing.retryDelay
            signal = .noSignal(message)
        }
        // Check the server's address on the first failure (the viewer may have
        // left home), so the quick retries can already use the new address.
        if failedAttempts == .zero || !isQuickRetry, let serverID = program?.item.serverID {
            onServerTrouble?(serverID)
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
        startWatchdog?.cancel()
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

private extension Duration {
    var milliseconds: Int64 {
        components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000
    }
}
