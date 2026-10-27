import Foundation
import RetroGuideKit

/// The viewer's audio and subtitle choices for what's on, and the subtitle timing.
struct TrackState: Encodable, Sendable {
    let selection: SelectionInfo?
    /// The scope of the choice covering what's on; `nil` is automatic.
    let audioScope: String?
    let subtitleScope: String?
    let subtitleDelay: TimeInterval
    let subtitleDelayText: String
}

struct TrackChoiceParams: Decodable, Sendable {
    /// `audio` or `subtitles`.
    let kind: String
    /// The track, or `nil` for subtitles off.
    let optionID: String?
    /// A ``TrackScope``, or `nil` to go back to automatic.
    let scope: String?
}

struct SubtitleNudgeParams: Decodable, Sendable {
    /// −1 earlier, +1 later, 0 back to the original timing.
    let direction: Int
    /// How many presses in a row (a held button moves faster).
    let repeatCount: Int
}

struct PlaybackEventParams: Decodable, Sendable {
    /// `started`, `progress`, `paused`, `resumed` or `stopped`.
    let event: String
    /// The tune the stream was started for; events for an older stream are dropped.
    let generation: Int
    let position: TimeInterval?
}

/// Everything the Options panel shows for what's on.
struct OptionsInfo: Encodable, Sendable {
    struct Choice: Encodable, Sendable {
        let id: String
        let title: String
    }

    let headline: String
    let channelID: String
    let channelTitle: String
    let isFavorite: Bool
    /// Scopes a track choice can cover, for "Audio for" and "Subtitles for".
    let scopes: [Choice]
    let ordering: String
    let orderings: [Choice]
    let orderingExplanation: String
    let canChangeOrdering: Bool
    let placement: String
    /// The show (or movie) can be taken off this channel.
    let isRemovable: Bool
    let canRemove: Bool
    let showID: String
    let isMovie: Bool
}

struct ChannelParams: Decodable, Sendable {
    let channelID: String
}

enum OptionsError: LocalizedError {
    case nothingPlaying

    var errorDescription: String? {
        "Nothing is playing."
    }
}

extension CoreState {
    private enum TrackKind {
        static let audio = "audio"
    }

    func trackState() -> TrackState? {
        guard let playing else { return nil }
        let delay = subtitleTiming.delay
        return TrackState(
            selection: playing.selection.map(SelectionInfo.init),
            audioScope: trackRules.audioRule(for: playing.program.item)?.scope.rawValue,
            subtitleScope: trackRules.subtitleRule(for: playing.program.item)?.scope.rawValue,
            subtitleDelay: delay,
            subtitleDelayText: SubtitleTiming.description(of: delay)
        )
    }

    /// Plays a track choice now and remembers it for everything its scope covers.
    func chooseTrack(_ params: TrackChoiceParams) async throws -> TrackState? {
        guard var playing, let tracks = playing.tracks else { throw OptionsError.nothingPlaying }
        let item = playing.program.item
        let scope = params.scope.flatMap(TrackScope.init(rawValue:))
        if params.kind == TrackKind.audio {
            if let scope, let option = tracks.audio.first(where: { $0.id == params.optionID }) ?? tracks.audioOption(for: playing.selection ?? tracks.selection) {
                trackRules.setAudio(AudioRule(option), scope: scope, for: item)
            } else {
                trackRules.resetAudio(for: item)
            }
        } else {
            if let scope {
                let option = params.optionID.flatMap { id in tracks.subtitles.first { $0.id == id } }
                trackRules.setSubtitles(SubtitleRule(option), scope: scope, for: item)
            } else {
                trackRules.resetSubtitles(for: item)
            }
        }
        store?.save(trackRules, file: CoreStore.File.trackRules)
        let selection = trackRules.selection(for: item, tracks: tracks)
        playing.selection = selection
        self.playing = playing
        subtitleTiming.select(selection.subtitle)
        await reporter.select(selection)
        return trackState()
    }

    /// Moves subtitles earlier or later for what's on (and the show's next episodes).
    func nudgeSubtitles(_ params: SubtitleNudgeParams) -> TrackState? {
        let step = SubtitleTiming.step(forRepeat: params.repeatCount)
        subtitleTiming.setDelay(params.direction == .zero ? .zero : subtitleTiming.delay + Double(params.direction.signum()) * step)
        store?.save(subtitleTiming.showOffsets, file: CoreStore.File.subtitleOffsets)
        return trackState()
    }

    func playbackEvent(_ params: PlaybackEventParams) async -> Done {
        guard params.generation == reportedTune else { return Done() }
        switch params.event {
        case "started": await reporter.started(position: params.position)
        case "paused": await reporter.pause(true, position: params.position)
        case "resumed": await reporter.pause(false, position: params.position)
        case "stopped":
            await reporter.end(position: params.position)
        default: await reporter.progress(position: params.position)
        }
        return Done()
    }

    func options(channelID: String) throws -> OptionsInfo {
        guard let channel = channel(withID: channelID) else { throw CoreError.unknownChannel }
        let access = ProAccess(isPro: isPro)
        let program = playing.flatMap { $0.channelID == channel.id ? $0.program : nil } ?? channel.timeline.program(at: .now)
        guard let item = program?.item else { throw OptionsError.nothingPlaying }
        let ordering = channel.definition.ordering
        return OptionsInfo(
            headline: item.headline,
            channelID: channel.id,
            channelTitle: "Channel \(channel.number) · \(channel.name)",
            isFavorite: viewing.isFavorite(channel),
            scopes: scopes(for: item, access: access),
            ordering: ordering.rawValue,
            orderings: ScheduleOrdering.allCases.map { OptionsInfo.Choice(id: $0.rawValue, title: $0.displayName) },
            orderingExplanation: ordering.explanation,
            canChangeOrdering: access.canChangeScheduling,
            placement: PlacementText.explanation(
                of: index?.placement(of: item, under: channel.definition.rule),
                title: item.headline,
                on: channel
            ),
            isRemovable: channel.definition.source != .series,
            canRemove: access.canRemoveFromChannels,
            showID: item.showID,
            isMovie: item.series == nil
        )
    }

    /// Scopes that mean something for `item` (movies have no seasons), the
    /// whole library with RetroGuide Pro.
    private func scopes(for item: MediaItem, access: ProAccess) -> [OptionsInfo.Choice] {
        let scopes: [TrackScope] = item.series == nil ? [.show, .library] : [.episode, .season, .show, .library]
        return scopes
            .filter { TrackRules.applies($0, to: item) && ($0 != .library || access.canChooseTracksForLibrary) }
            .map { OptionsInfo.Choice(id: $0.rawValue, title: scopeTitle($0, for: item)) }
    }

    private func scopeTitle(_ scope: TrackScope, for item: MediaItem) -> String {
        switch scope {
        case .episode: return "This episode"
        case .season: return item.series?.seasonNumber.map { "Season \($0)" } ?? "This season"
        case .show: return item.series.map { "Every episode of \($0.title)" } ?? "This movie"
        case .library:
            let library = index?.facets.libraries.first { $0.id == item.libraryID }?.name ?? "this library"
            return "Everything in \(library)"
        }
    }
}
