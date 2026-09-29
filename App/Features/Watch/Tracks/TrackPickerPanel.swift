import RetroGuideKit
import SwiftUI

/// Audio and subtitle choices for what's on now. Changes apply to the live
/// picture right away, and are remembered for every episode of the show (by
/// language, like PASTA) or just this one.
struct TrackPickerPanel: View {
    let tuner: Tuner

    @Environment(\.theme) private var theme
    @State private var appliesToWholeShow = true
    /// Focus starts on the current subtitle choice when the panel opens.
    @FocusState private var focusedRow: String?

    private enum Row {
        static let subtitlesOff = "subtitles.off"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                header
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignTokens.Spacing.lg)
        }
        .scrollClipDisabled()
        .onAppear(perform: focusCurrentChoice)
    }

    private func focusCurrentChoice() {
        let current = tuner.currentSelection.flatMap { tuner.currentTracks?.subtitleOption(for: $0) }
        // After the panel is on screen, so the row can take focus.
        Task { @MainActor in
            focusedRow = current?.id ?? Row.subtitlesOff
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("Audio & Subtitles")
                .font(Typography.title)
                .foregroundStyle(theme.textPrimary)
            if let program = tuner.program {
                Text(program.item.headline)
                    .font(Typography.bodyEmphasis)
                    .foregroundStyle(theme.accent)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !tuner.engine.switchesTracksLive {
            note("Choosing audio and subtitles needs the RetroGuide Player. You can switch to it in Settings › Playback › Player.")
        } else if let tracks = tuner.currentTracks, let selection = tuner.currentSelection {
            choices(tracks: tracks, selection: selection)
        } else if tuner.signal == .tuning {
            note("Loading this program's tracks…")
        } else {
            note("This program's audio and subtitle tracks aren't available.")
        }
    }

    @ViewBuilder
    private func choices(tracks: ItemTracks, selection: TrackSelection) -> some View {
        let audio = tracks.audioOption(for: selection)
        let subtitle = tracks.subtitleOption(for: selection)
        if tracks.audio.count > 1 {
            SettingsSection("Audio") {
                ForEach(tracks.audio) { option in
                    CheckmarkRow(title: option.title, isSelected: option == audio) {
                        tuner.chooseTracks(audio: option, subtitle: subtitle, forWholeShow: isForWholeShow)
                    }
                    .focused($focusedRow, equals: option.id)
                }
            }
        }
        SettingsSection("Subtitles") {
            CheckmarkRow(title: "Off", isSelected: subtitle == nil) {
                tuner.chooseTracks(audio: nil, subtitle: nil, forWholeShow: isForWholeShow)
            }
            .focused($focusedRow, equals: Row.subtitlesOff)
            ForEach(tracks.subtitles) { option in
                CheckmarkRow(title: option.title, isSelected: option == subtitle) {
                    tuner.chooseTracks(audio: nil, subtitle: option, forWholeShow: isForWholeShow)
                }
                .focused($focusedRow, equals: option.id)
            }
        }
        if let show = tuner.program?.item.series?.title {
            SettingsSection("Apply To") {
                CheckmarkRow(title: "Every episode of \(show)", detail: "Matched by language on each episode.", isSelected: appliesToWholeShow) {
                    appliesToWholeShow = true
                }
                CheckmarkRow(title: "Just this episode", isSelected: !appliesToWholeShow) {
                    appliesToWholeShow = false
                }
            }
        }
        if tuner.hasShowTrackPreference {
            Button("Back to automatic", systemImage: "arrow.uturn.backward") {
                tuner.resetTracksToAutomatic()
            }
            .buttonStyle(.retro)
        }
    }

    /// Movies have no other episodes, so their choice is remembered for the movie.
    private var isForWholeShow: Bool {
        tuner.program?.item.series == nil || appliesToWholeShow
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Typography.body)
            .foregroundStyle(theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
