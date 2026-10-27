import Foundation
import RetroGuideKit

struct TuneParams: Decodable, Sendable {
    let channelID: String
    /// Counts up with every tune the app starts; an older tune finishing late isn't kept.
    let generation: Int
    /// Watch from the beginning: this program, from `position` (0 when omitted),
    /// off the channel's clock.
    let programID: String?
    let position: TimeInterval?
}

/// What to show on a channel right now.
struct TuneResult: Encodable, Sendable {
    let channelID: String
    let program: ProgramInfo
    /// Set when the program's content is over and the next one starts then.
    let intermissionUntil: Date?
    let stream: StreamInfo?
    let tracks: TracksInfo?
    let trackState: TrackState?
}

struct StreamInfo: Encodable, Sendable {
    let url: String
    /// Seconds into the file to start (the live position).
    let position: TimeInterval
    let serverID: String
    let sessionID: String
    /// The server repackages this stream and must be told when it ends.
    let needsTeardown: Bool
    /// mpv's network cache, from the server's buffering setting.
    let maxBytes: String
    let readaheadSeconds: String
}

struct TracksInfo: Encodable, Sendable {
    let audio: [TrackInfo]
    let subtitles: [TrackInfo]
    let selection: SelectionInfo
}

struct TrackInfo: Encodable, Sendable {
    let id: String
    let title: String
    let language: String?
    let isForced: Bool
    /// The container stream index (embedded tracks).
    let streamIndex: Int?
    /// The sidecar file (external subtitles).
    let url: String?
}

/// A ``TrackSelection`` as it crosses the bridge.
struct SelectionInfo: Codable, Sendable {
    let audioStreamIndex: Int?
    /// `none`, `embedded` or `external`.
    let subtitle: String
    let subtitleStreamIndex: Int?
    let subtitleURL: String?

    private enum Subtitle {
        static let none = "none"
        static let embedded = "embedded"
        static let external = "external"
    }

    init(_ selection: TrackSelection) {
        audioStreamIndex = selection.audioStreamIndex
        switch selection.subtitle {
        case .none:
            (subtitle, subtitleStreamIndex, subtitleURL) = (Subtitle.none, nil, nil)
        case let .embedded(index):
            (subtitle, subtitleStreamIndex, subtitleURL) = (Subtitle.embedded, index, nil)
        case let .external(url):
            (subtitle, subtitleStreamIndex, subtitleURL) = (Subtitle.external, nil, url.absoluteString)
        }
    }

    var trackSelection: TrackSelection {
        let choice: SubtitleChoice = switch subtitle {
        case Subtitle.embedded: subtitleStreamIndex.map { .embedded(streamIndex: $0) } ?? .none
        case Subtitle.external: subtitleURL.flatMap(URL.init(string:)).map { .external($0) } ?? .none
        default: .none
        }
        return TrackSelection(audioStreamIndex: audioStreamIndex, subtitle: choice)
    }
}

struct TrackCommandParams: Decodable, Sendable {
    let selection: SelectionInfo
    /// mpv's `track-list` property, as JSON.
    let trackList: String
}

struct EndStreamParams: Decodable, Sendable {
    let serverID: String
    let sessionID: String
}

/// The stream on the player now, for track choices and playback reports.
struct Playing: Sendable {
    let program: ScheduledProgram
    let channelID: String
    let tracks: ItemTracks?
    var selection: TrackSelection?
}

extension CoreState {
    /// mpv plays any container and codec, so servers send the original file.
    private static let capabilities = PlaybackCapabilities.universal

    private enum Timing {
        /// Servers that start streams at a position can only start on whole
        /// seconds; if preparing put it this far behind, it's requested again.
        static let serverPositionTolerance: TimeInterval = 1
        /// How far around now a program to watch from the beginning is looked for.
        static let programSearchWindow: TimeInterval = 24 * ScheduleConstants.secondsPerHour
    }

    /// The program on `channelID` now (or the one asked for), and the stream to show it.
    func tune(_ params: TuneParams) async throws -> TuneResult {
        latestTune = max(latestTune, params.generation)
        guard let channel = channel(withID: params.channelID) else { throw CoreError.unknownChannel }
        let now = Date.now
        let independent = params.programID.flatMap { program(withID: $0, on: channel, near: now) }
        if params.programID != nil, independent == nil { throw CoreError.nothingScheduled }
        guard let program = independent ?? channel.timeline.program(at: now) else { throw CoreError.nothingScheduled }
        if independent == nil, program.isInIntermission(at: now) {
            return TuneResult(channelID: channel.id, program: programInfo(program), intermissionUntil: program.slotEnd, stream: nil, tracks: nil, trackState: nil)
        }
        try checkParental(program.item)
        guard let client = clients[program.item.serverID] else { throw CoreError.unknownServer }
        let independentPosition = independent.map { _ in params.position ?? .zero }
        let prepared = try await client.preparePlayback(
            for: program.item,
            startingAt: independentPosition ?? program.elapsed(at: now),
            capabilities: Self.capabilities,
            preferences: languagePreferences
        )
        var request = prepared.request
        var tracks = prepared.tracks
        // Preparing takes a moment: a server that starts at a position is asked again if it fell behind.
        if independentPosition == nil, request.startsAtPosition,
           program.elapsed(at: .now) - request.startPosition >= Timing.serverPositionTolerance {
            if request.needsTeardown { await client.endStream(sessionID: request.sessionID) }
            let previousVersion = request.versionIndex
            request = try await client.streamRequest(for: program.item, startingAt: program.elapsed(at: .now), capabilities: Self.capabilities)
            if request.versionIndex != previousVersion {
                tracks = await client.tracks(for: program.item, version: request.versionIndex, preferences: languagePreferences)
            }
        }
        request = request.starting(at: independentPosition ?? program.elapsed(at: .now))
        let selection = tracks.map { trackRules.selection(for: program.item, tracks: $0) }
        if params.generation == latestTune {
            playing = Playing(program: program, channelID: channel.id, tracks: tracks, selection: selection)
            subtitleTiming.prepare(
                itemID: program.item.id,
                versionIndex: request.versionIndex,
                show: SubtitleTimingState.show(of: program.item),
                subtitle: selection?.subtitle ?? .none
            )
            reportedTune = params.generation
            await reporter.prepare(client: client, item: program.item, request: request, tracks: tracks, selection: selection)
        }
        let buffer = MPVBufferSettings(request.buffer)
        let stream = StreamInfo(
            url: request.url.absoluteString,
            position: request.startPosition,
            serverID: program.item.serverID,
            sessionID: request.sessionID,
            needsTeardown: request.needsTeardown,
            maxBytes: buffer.maxBytes,
            readaheadSeconds: buffer.readaheadSeconds
        )
        return TuneResult(
            channelID: channel.id,
            program: programInfo(program),
            intermissionUntil: nil,
            stream: stream,
            tracks: tracks.map { tracksInfo($0, selection: selection) },
            trackState: trackState()
        )
    }

    private func program(withID id: String, on channel: Channel, near date: Date) -> ScheduledProgram? {
        let window = DateInterval(start: date.addingTimeInterval(-Timing.programSearchWindow), duration: 2 * Timing.programSearchWindow)
        return channel.timeline.programs(overlapping: window).first { $0.id == id }
    }

    func endStream(_ params: EndStreamParams) async -> Done {
        await clients[params.serverID]?.endStream(sessionID: params.sessionID)
        return Done()
    }

    private func tracksInfo(_ tracks: ItemTracks, selection: TrackSelection?) -> TracksInfo {
        func info(_ option: TrackOption) -> TrackInfo {
            let (streamIndex, url): (Int?, String?) = switch option.source {
            case let .embedded(index): (index, nil)
            case let .external(url): (nil, url.absoluteString)
            }
            return TrackInfo(id: option.id, title: option.title, language: option.language, isForced: option.isForced, streamIndex: streamIndex, url: url)
        }
        return TracksInfo(audio: tracks.audio.map(info), subtitles: tracks.subtitles.map(info), selection: SelectionInfo(selection ?? tracks.selection))
    }
}
