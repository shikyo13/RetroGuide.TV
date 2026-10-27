import Foundation
import Testing
@testable import RetroGuideKit

struct SubtitleAutoSelectorTests {
    private let spanish = SubtitleCandidate(language: "spa", isForced: false)
    private let englishForced = SubtitleCandidate(language: "eng", isForced: true)
    private let english = SubtitleCandidate(language: "eng", isForced: false)

    private func preferences(_ mode: SubtitleMode) -> LanguagePreferences {
        LanguagePreferences(audioLanguage: "en", subtitleLanguage: "en", subtitleMode: mode)
    }

    @Test func foreignAudioShowsSubtitlesInThePreferredLanguage() {
        let choice = SubtitleAutoSelector.choose(
            from: [spanish, englishForced, english], audioLanguage: "jpn", preferences: preferences(.foreignAudio)
        )
        #expect(choice == 2)
    }

    @Test func matchingAudioShowsOnlyForcedSubtitles() {
        let candidates = [spanish, english, englishForced]
        #expect(SubtitleAutoSelector.choose(from: candidates, audioLanguage: "eng", preferences: preferences(.foreignAudio)) == 2)
        #expect(SubtitleAutoSelector.choose(from: [english], audioLanguage: "en-US", preferences: preferences(.foreignAudio)) == nil)
    }

    @Test func manualNeverTurnsSubtitlesOn() {
        #expect(SubtitleAutoSelector.choose(from: [english], audioLanguage: "jpn", preferences: preferences(.manual)) == nil)
    }

    @Test(arguments: ["eng", "jpn", "und", nil] as [String?])
    func forcedOnlyNeverSelectsOrdinarySubtitles(audioLanguage: String?) {
        #expect(SubtitleAutoSelector.choose(
            from: [english, spanish], audioLanguage: audioLanguage, preferences: preferences(.forcedOnly)
        ) == nil)
        #expect(SubtitleAutoSelector.choose(
            from: [english, englishForced], audioLanguage: audioLanguage, preferences: preferences(.forcedOnly)
        ) == 1)
    }

    @Test func forcedOnlyRequiresThePreferredLanguage() {
        let spanishForced = SubtitleCandidate(language: "spa", isForced: true)
        #expect(SubtitleAutoSelector.choose(
            from: [spanishForced, english], audioLanguage: "jpn", preferences: preferences(.forcedOnly)
        ) == nil)
    }

    @Test func alwaysPrefersFullSubtitlesOverForced() {
        let choice = SubtitleAutoSelector.choose(from: [englishForced, english], audioLanguage: "eng", preferences: preferences(.always))
        #expect(choice == 1)
    }

    @Test func noSubtitleInThePreferredLanguageMeansNone() {
        #expect(SubtitleAutoSelector.choose(from: [spanish], audioLanguage: "jpn", preferences: preferences(.always)) == nil)
    }

    @Test func unknownAudioLanguageIsNotTreatedAsForeign() {
        #expect(SubtitleAutoSelector.choose(from: [english], audioLanguage: "und", preferences: preferences(.foreignAudio)) == nil)
        #expect(SubtitleAutoSelector.choose(from: [english], audioLanguage: nil, preferences: preferences(.foreignAudio)) == nil)
    }

    @Test func languageCodesMatchAcrossFormats() {
        #expect(LanguageCode.normalized("eng") == "en")
        #expect(LanguageCode.normalized("en-US") == "en")
        #expect(LanguageCode.normalized("JPN") == "ja")
        #expect(LanguageCode.normalized("und") == nil)
    }
}

struct PlexTrackSelectionMapperTests {
    private let audio = PlexAPI.StreamType.audio
    private let subtitle = PlexAPI.StreamType.subtitle
    private let preferences = LanguagePreferences(audioLanguage: "en", subtitleLanguage: "en", subtitleMode: .foreignAudio)

    /// An anime episode with Japanese audio and Spanish and English subtitles.
    private var episode: [PlexStream] {
        [
            PlexStream(streamType: audio, index: 1, key: nil, selected: true, languageCode: "jpn"),
            PlexStream(streamType: subtitle, index: 4, key: nil, selected: nil, languageCode: "spa"),
            PlexStream(streamType: subtitle, index: 7, key: nil, selected: nil, languageTag: "en", languageCode: "eng"),
        ]
    }

    @Test func picksSubtitlesFromAccountPreferencesWhenNoneAreChosen() {
        let selection = PlexTrackSelectionMapper.selection(from: episode, preferences: preferences) { _ in nil }
        #expect(selection == TrackSelection(audioStreamIndex: 1, subtitle: .embedded(streamIndex: 7)))
    }

    @Test func theViewersOwnChoiceWins() {
        var streams = episode
        streams[1] = PlexStream(streamType: subtitle, index: 4, key: nil, selected: true, languageCode: "spa")
        let selection = PlexTrackSelectionMapper.selection(from: streams, preferences: preferences) { _ in nil }
        #expect(selection.subtitle == .embedded(streamIndex: 4))
    }

    @Test("External VobSub subtitles are fetched as .idx, so the player finds the .sub beside them")
    func vobSubKeepsItsExtension() {
        var vobSub = PlexStream(streamType: subtitle, index: nil, key: "/library/streams/77", selected: true, languageCode: "eng")
        vobSub.codec = "idx"
        var srt = PlexStream(streamType: subtitle, index: nil, key: "/library/streams/78", selected: true, languageCode: "eng")
        srt.codec = "srt"
        let url = { (key: String) in URL(string: "http://server" + key) }
        #expect(PlexTrackSelectionMapper.selection(from: [vobSub], preferences: nil, externalURL: url).subtitle == .external(URL(string: "http://server/library/streams/77.idx")!))
        #expect(PlexTrackSelectionMapper.selection(from: [srt], preferences: nil, externalURL: url).subtitle == .external(URL(string: "http://server/library/streams/78")!))
    }

    @Test func withoutPreferencesOnlyChosenTracksAreUsed() {
        let selection = PlexTrackSelectionMapper.selection(from: episode, preferences: nil) { _ in nil }
        #expect(selection.subtitle == SubtitleChoice.none)
    }
}

@Suite("Plex track list")
struct PlexTrackListTests {
    @Test("Every audio and subtitle track is offered, named the way Plex names it")
    func listsTracks() throws {
        let json = """
        [
          {"streamType": 1, "index": 0},
          {"streamType": 2, "index": 1, "languageCode": "jpn", "selected": true, "extendedDisplayTitle": "Japanese (AAC Stereo)"},
          {"streamType": 2, "index": 2, "languageCode": "eng", "displayTitle": "English (AAC Stereo)"},
          {"streamType": 3, "index": 3, "languageCode": "eng", "displayTitle": "English (ASS)", "selected": true},
          {"streamType": 3, "key": "/library/streams/9", "languageCode": "eng", "forced": true, "displayTitle": "English Forced (SRT External)"}
        ]
        """
        let streams = try JSONDecoder().decode([PlexStream].self, from: Data(json.utf8))
        let url = URL(string: "https://server/library/streams/9")!
        let tracks = PlexTrackSelectionMapper.tracks(from: streams, preferences: nil) { _ in url }
        #expect(tracks.audio.map(\.title) == ["Japanese (AAC Stereo)", "English (AAC Stereo)"])
        #expect(tracks.subtitles.map(\.title) == ["English (ASS)", "English Forced (SRT External)"])
        #expect(tracks.subtitles[1].isForced)
        #expect(tracks.subtitles[1].source == .external(url))
        #expect(tracks.audioOption(for: tracks.selection)?.title == "Japanese (AAC Stereo)")
        #expect(tracks.subtitleOption(for: tracks.selection)?.title == "English (ASS)")
    }
}
