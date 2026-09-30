import RetroGuideKit
import SwiftUI

/// Options for what's on now: audio and subtitles (applied to the live picture
/// right away, and remembered for every episode of the show by language, like
/// PASTA, or just this one) and the channel's schedule order.
struct WatchOptionsPanel: View {
    private enum ChoiceID {
        static let subtitlesOff = "subtitles.off"
        static let wholeShow = "scope.show"
        static let thisEpisode = "scope.episode"
    }

    let tuner: Tuner

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    /// Shown right away; rebuilding a large lineup takes a few seconds.
    @State private var pendingOrdering: ScheduleOrdering?
    @State private var appliesToWholeShow = true
    /// Focus starts on Subtitles, the usual reason to open the panel.
    @FocusState private var isSubtitlesFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                header
                SettingsSection("Audio & Subtitles") {
                    content
                }
                if let channel = tuner.channel {
                    SettingsSection("Channel \(channel.number) · \(channel.name)") {
                        scheduleOrder(for: channel)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignTokens.Spacing.lg)
        }
        .scrollClipDisabled()
        .onAppear {
            // After the panel is on screen, so the menu can take focus.
            Task { @MainActor in isSubtitlesFocused = true }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("Options")
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
        VStack(spacing: DesignTokens.Spacing.sm) {
            OptionMenu(
                title: "Audio",
                systemImage: "speaker.wave.2",
                choices: tracks.audio.map { OptionMenu.Choice(id: $0.id, title: $0.title) },
                selection: Binding(
                    get: { audio?.id ?? "" },
                    set: { id in
                        guard let option = tracks.audio.first(where: { $0.id == id }) else { return }
                        tuner.chooseTracks(audio: option, subtitle: subtitle, forWholeShow: isForWholeShow)
                    }
                )
            )
            .disabled(tracks.audio.count < 2)
            OptionMenu(
                title: "Subtitles",
                systemImage: "captions.bubble",
                choices: [OptionMenu.Choice(id: ChoiceID.subtitlesOff, title: "Off")]
                    + tracks.subtitles.map { OptionMenu.Choice(id: $0.id, title: $0.title) },
                selection: Binding(
                    get: { subtitle?.id ?? ChoiceID.subtitlesOff },
                    set: { id in
                        tuner.chooseTracks(audio: nil, subtitle: tracks.subtitles.first { $0.id == id }, forWholeShow: isForWholeShow)
                    }
                )
            )
            .focused($isSubtitlesFocused)
            if let show = tuner.program?.item.series?.title {
                OptionMenu(
                    title: "Use for",
                    systemImage: "square.stack",
                    choices: [
                        OptionMenu.Choice(id: ChoiceID.wholeShow, title: "Every episode of \(show)"),
                        OptionMenu.Choice(id: ChoiceID.thisEpisode, title: "Just this episode"),
                    ],
                    selection: Binding(
                        get: { appliesToWholeShow ? ChoiceID.wholeShow : ChoiceID.thisEpisode },
                        set: { appliesToWholeShow = $0 == ChoiceID.wholeShow }
                    )
                )
            }
        }
        if tuner.hasShowTrackPreference {
            Button("Back to automatic", systemImage: "arrow.uturn.backward") {
                tuner.resetTracksToAutomatic()
            }
            .buttonStyle(.retro)
        }
    }

    @ViewBuilder
    private func scheduleOrder(for channel: Channel) -> some View {
        let current = pendingOrdering ?? channel.definition.ordering
        OptionMenu(
            title: "Schedule order",
            systemImage: "shuffle",
            choices: ScheduleOrdering.allCases.map { OptionMenu.Choice(id: $0.rawValue, title: $0.displayName) },
            selection: Binding(
                get: { current.rawValue },
                set: { rawValue in
                    guard let ordering = ScheduleOrdering(rawValue: rawValue), ordering != current else { return }
                    pendingOrdering = ordering
                    app.setOrdering(ordering, for: channel.definition)
                }
            )
        )
        .disabled(!app.pro.access.canChangeScheduling)
        .onChange(of: channel.definition.ordering) { _, ordering in
            if ordering == pendingOrdering {
                pendingOrdering = nil
            }
        }
        if app.pro.access.canChangeScheduling {
            note(current.explanation)
            ScheduleUpdatingNote(isVisible: pendingOrdering != nil && app.isRebuildingLineup)
        } else {
            note("Changing a channel's schedule order is part of RetroGuide Pro (Settings › RetroGuide Pro).")
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
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
