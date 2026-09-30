import Foundation

/// One audio or subtitle track the viewer can pick.
public struct TrackOption: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case audio
        case subtitle
    }

    public let kind: Kind
    /// Where the track lives: a stream inside the file, or a sidecar subtitle file.
    public let source: Source
    /// ISO 639 code as the server reports it, if known.
    public let language: String?
    /// What the server calls the track, e.g. "English (AAC Stereo)" or "English (Signs & Songs)".
    public let title: String
    public let isForced: Bool

    public enum Source: Sendable, Hashable {
        case embedded(streamIndex: Int)
        case external(URL)
    }

    public init(kind: Kind, source: Source, language: String?, title: String, isForced: Bool) {
        self.kind = kind
        self.source = source
        self.language = language
        self.title = title
        self.isForced = isForced
    }

    public var id: String {
        switch source {
        case let .embedded(index): "\(kind)#\(index)"
        case let .external(url): "\(kind)#\(url.absoluteString)"
        }
    }

    /// The subtitle choice that shows this track.
    var subtitleChoice: SubtitleChoice {
        switch source {
        case let .embedded(index): .embedded(streamIndex: index)
        case let .external(url): .external(url)
        }
    }

    var streamIndex: Int? {
        guard case let .embedded(index) = source else { return nil }
        return index
    }
}

/// Every audio and subtitle track of an item, and the ones the server (or the
/// viewer's account settings) would play.
public struct ItemTracks: Sendable, Hashable {
    public let audio: [TrackOption]
    public let subtitles: [TrackOption]
    public let selection: TrackSelection

    public init(audio: [TrackOption], subtitles: [TrackOption], selection: TrackSelection) {
        self.audio = audio
        self.subtitles = subtitles
        self.selection = selection
    }

    /// The audio track `selection` plays, if it names one.
    public func audioOption(for selection: TrackSelection) -> TrackOption? {
        selection.audioStreamIndex.flatMap { index in audio.first { $0.streamIndex == index } }
    }

    /// The subtitle track `selection` shows, or `nil` when subtitles are off.
    public func subtitleOption(for selection: TrackSelection) -> TrackOption? {
        subtitles.first { $0.subtitleChoice == selection.subtitle }
    }


}
