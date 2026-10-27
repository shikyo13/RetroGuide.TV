import Foundation
import Testing
@testable import RetroGuideKit

@Suite("Track rules")
struct TrackRulesTests {
    private static func audio(_ index: Int, _ language: String, _ title: String) -> TrackOption {
        TrackOption(kind: .audio, source: .embedded(streamIndex: index), language: language, title: title, isForced: false)
    }

    private static func subtitle(_ index: Int, _ language: String, _ title: String, forced: Bool = false) -> TrackOption {
        TrackOption(kind: .subtitle, source: .embedded(streamIndex: index), language: language, title: title, isForced: forced)
    }

    private static func episode(_ number: Int, season: Int = 1, show: String = "Show", library: String = "server/1") -> MediaItem {
        MediaItem(
            serverID: "server", itemKey: "\(show)-\(season)-\(number)", libraryID: library, kind: .episode, title: "E\(number)",
            series: SeriesInfo(key: show, title: show, seasonNumber: season, episodeNumber: number), duration: 1_400
        )
    }

    /// An anime episode: Japanese, English dub and a Japanese commentary;
    /// signs-only and full dialogue English subtitles.
    private static let tracks = ItemTracks(
        audio: [audio(1, "jpn", "FLAC 2.0 (Japanese)"), audio(2, "eng", "AAC 2.0 [Golumpa] (English)"), audio(3, "jpn", "Commentary (Japanese FLAC Stereo)")],
        subtitles: [subtitle(4, "eng", "Signs & Songs [Edited-SubsPlease] (English ASS)"), subtitle(5, "eng", "Dialogue [SubsPlease] (English ASS)")],
        selection: TrackSelection(audioStreamIndex: 1, subtitle: .embedded(streamIndex: 4))
    )

    /// Another release of the same show, tracks named and numbered differently.
    private static let otherRelease = ItemTracks(
        audio: [audio(1, "ja", "Commentary"), audio(2, "ja", "Japanese (TRUEHD Stereo)"), audio(3, "en", "English (TRUEHD 5.1)")],
        subtitles: [subtitle(7, "en", "Dialogue (English PGS)"), subtitle(8, "en", "Signs / Songs (English PGS)")],
        selection: TrackSelection(audioStreamIndex: 1, subtitle: .none)
    )

    @Test("Dialogue subtitles and main audio carry over by language and kind, not track number")
    func matchesAcrossReleases() {
        var rules = TrackRules()
        rules.setAudio(AudioRule(Self.tracks.audio[0]), scope: .show, for: Self.episode(1))
        rules.setSubtitles(SubtitleRule(Self.tracks.subtitles[1]), scope: .show, for: Self.episode(1))
        let selection = rules.selection(for: Self.episode(2), tracks: Self.otherRelease)
        #expect(selection == TrackSelection(audioStreamIndex: 2, subtitle: .embedded(streamIndex: 7)))
    }

    @Test("Audio and subtitles are remembered at their own scopes")
    func separateScopes() {
        var rules = TrackRules()
        rules.setAudio(AudioRule(Self.tracks.audio[1]), scope: .library, for: Self.episode(1))
        rules.setSubtitles(SubtitleRule(nil), scope: .episode, for: Self.episode(1))
        #expect(rules.selection(for: Self.episode(1), tracks: Self.tracks) == TrackSelection(audioStreamIndex: 2, subtitle: .none))
        // Another episode: library audio, server's subtitles.
        #expect(rules.selection(for: Self.episode(2), tracks: Self.tracks) == TrackSelection(audioStreamIndex: 2, subtitle: .embedded(streamIndex: 4)))
        #expect(rules.audioRule(for: Self.episode(2))?.scope == .library)
        #expect(rules.subtitleRule(for: Self.episode(2)) == nil)
    }

    @Test("The most specific choice wins; choosing for a show replaces its episodes' choices")
    func precedence() {
        var rules = TrackRules()
        rules.setSubtitles(SubtitleRule(Self.tracks.subtitles[0]), scope: .season, for: Self.episode(1))
        rules.setSubtitles(SubtitleRule(nil), scope: .episode, for: Self.episode(3))
        #expect(rules.subtitleRule(for: Self.episode(3))?.scope == .episode)
        #expect(rules.subtitleRule(for: Self.episode(2))?.scope == .season)
        rules.setSubtitles(SubtitleRule(Self.tracks.subtitles[1]), scope: .show, for: Self.episode(1))
        #expect(rules.subtitleRule(for: Self.episode(3))?.scope == .show)
        #expect(rules.subtitleRule(for: Self.episode(1, season: 2))?.scope == .show)
    }

    @Test("A season choice stays within its season and show")
    func seasonBoundaries() {
        var rules = TrackRules()
        rules.setAudio(AudioRule(Self.tracks.audio[1]), scope: .season, for: Self.episode(1))
        #expect(rules.audioRule(for: Self.episode(5))?.scope == .season)
        #expect(rules.audioRule(for: Self.episode(5, season: 2)) == nil)
        #expect(rules.audioRule(for: Self.episode(1, show: "Other")) == nil)
    }

    @Test("Going back to automatic keeps the library default")
    func reset() {
        var rules = TrackRules()
        rules.setAudio(AudioRule(Self.tracks.audio[1]), scope: .library, for: Self.episode(1))
        rules.setAudio(AudioRule(Self.tracks.audio[0]), scope: .show, for: Self.episode(1))
        rules.setSubtitles(SubtitleRule(nil), scope: .episode, for: Self.episode(2))
        rules.reset(for: Self.episode(2))
        #expect(rules.audioRule(for: Self.episode(2))?.scope == .library)
        #expect(rules.subtitleRule(for: Self.episode(2)) == nil)
    }

    @Test("Movies have no season scope")
    func movies() {
        let movie = MediaItem(serverID: "server", itemKey: "m1", libraryID: "server/2", kind: .movie, title: "Movie", duration: 5_400)
        #expect(!TrackRules.applies(.season, to: movie))
        #expect(TrackRules.applies(.show, to: movie))
    }

    @Test("Rules survive saving")
    func codable() throws {
        var rules = TrackRules()
        rules.setAudio(AudioRule(Self.tracks.audio[0]), scope: .show, for: Self.episode(1))
        rules.setSubtitles(SubtitleRule(Self.tracks.subtitles[1]), scope: .library, for: Self.episode(1))
        let decoded = try JSONDecoder().decode(TrackRules.self, from: JSONEncoder().encode(rules))
        #expect(decoded == rules)
    }
}
