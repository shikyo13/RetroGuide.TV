import Foundation
import RetroGuideKit

struct TuneParams: Decodable, Sendable {
    let channelID: String
}

/// What to show on a channel right now.
struct TuneResult: Encodable, Sendable {
    let channelID: String
    let program: ProgramInfo
    /// Set when the program's content is over and the next one starts then.
    let intermissionUntil: Date?
    let stream: StreamInfo?
    let tracks: TracksInfo?
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

extension CoreState {
    /// mpv plays any container and codec, so servers send the original file.
    private static let capabilities = PlaybackCapabilities.universal

    /// The program on `channelID` now, and the stream to show it from its live position.
    func tune(_ params: TuneParams) async throws -> TuneResult {
        guard let channel = channel(withID: params.channelID) else { throw CoreError.unknownChannel }
        let now = Date.now
        guard let program = channel.timeline.program(at: now) else { throw CoreError.nothingScheduled }
        if program.isInIntermission(at: now) {
            return TuneResult(channelID: channel.id, program: programInfo(program), intermissionUntil: program.slotEnd, stream: nil, tracks: nil)
        }
        guard let client = clients[program.item.serverID] else { throw CoreError.unknownServer }
        let prepared = try await client.preparePlayback(
            for: program.item,
            startingAt: program.elapsed(at: now),
            capabilities: Self.capabilities,
            preferences: languagePreferences
        )
        // Preparing takes a moment: join where the program is now.
        let request = prepared.request.starting(at: program.elapsed(at: .now))
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
            tracks: prepared.tracks.map(tracksInfo)
        )
    }

    func endStream(_ params: EndStreamParams) async -> Done {
        await clients[params.serverID]?.endStream(sessionID: params.sessionID)
        return Done()
    }

    private func tracksInfo(_ tracks: ItemTracks) -> TracksInfo {
        func info(_ option: TrackOption) -> TrackInfo {
            let (streamIndex, url): (Int?, String?) = switch option.source {
            case let .embedded(index): (index, nil)
            case let .external(url): (nil, url.absoluteString)
            }
            return TrackInfo(id: option.id, title: option.title, language: option.language, isForced: option.isForced, streamIndex: streamIndex, url: url)
        }
        return TracksInfo(audio: tracks.audio.map(info), subtitles: tracks.subtitles.map(info), selection: SelectionInfo(tracks.selection))
    }
}
