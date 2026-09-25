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

    @Test func withoutPreferencesOnlyChosenTracksAreUsed() {
        let selection = PlexTrackSelectionMapper.selection(from: episode, preferences: nil) { _ in nil }
        #expect(selection.subtitle == SubtitleChoice.none)
    }
}
