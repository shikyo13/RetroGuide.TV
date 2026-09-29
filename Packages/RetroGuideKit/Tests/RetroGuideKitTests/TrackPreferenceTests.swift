import Foundation
import Testing
@testable import RetroGuideKit

@Suite("Track preferences")
struct TrackPreferenceTests {
    private static func audio(_ index: Int, _ language: String) -> TrackOption {
        TrackOption(kind: .audio, source: .embedded(streamIndex: index), language: language, title: language, isForced: false)
    }

    private static func subtitle(_ index: Int, _ language: String, forced: Bool = false, title: String? = nil) -> TrackOption {
        TrackOption(kind: .subtitle, source: .embedded(streamIndex: index), language: language, title: title ?? language, isForced: forced)
    }

    /// An anime episode: Japanese and English audio, full and signs-only English subtitles.
    private static let episode = ItemTracks(
        audio: [audio(1, "jpn"), audio(2, "eng")],
        subtitles: [subtitle(3, "eng", title: "English (Full)"), subtitle(4, "eng", forced: true, title: "English (Signs)")],
        selection: TrackSelection(audioStreamIndex: 1, subtitle: .embedded(streamIndex: 3))
    )

    @Test("Subtitles off stays off on every episode")
    func off() {
        let preference = TrackPreference(subtitles: .off)
        #expect(preference.selection(for: Self.episode) == TrackSelection(audioStreamIndex: 1, subtitle: .none))
    }

    @Test("A dub with signs-only subtitles carries over by language, not track number")
    func dubWithSigns() {
        let preference = TrackPreference(audio: Self.episode.audio[1], subtitle: Self.episode.subtitles[1], subtitlesOff: false)
        let other = ItemTracks(
            audio: [Self.audio(7, "en"), Self.audio(8, "ja")],
            subtitles: [Self.subtitle(9, "en", forced: true, title: "English (Signs)"), Self.subtitle(10, "en", title: "English (Full)")],
            selection: TrackSelection(audioStreamIndex: 8, subtitle: .none)
        )
        #expect(preference.selection(for: other) == TrackSelection(audioStreamIndex: 7, subtitle: .embedded(streamIndex: 9)))
    }

    @Test("A missing language falls back to the server's audio and no subtitles")
    func missing() {
        let preference = TrackPreference(audioLanguage: "fr", subtitles: .track(language: "fr", isForced: false, title: "French"))
        #expect(preference.selection(for: Self.episode) == TrackSelection(audioStreamIndex: 1, subtitle: .none))
    }

    @Test("Automatic keeps the server's choice")
    func automatic() {
        #expect(TrackPreference().selection(for: Self.episode) == Self.episode.selection)
    }

    @Test("Preferences survive saving")
    func codable() throws {
        let preference = TrackPreference(audioLanguage: "jpn", subtitles: .track(language: "eng", isForced: false, title: "English (Full)"))
        let data = try JSONEncoder().encode(preference)
        #expect(try JSONDecoder().decode(TrackPreference.self, from: data) == preference)
    }
}
