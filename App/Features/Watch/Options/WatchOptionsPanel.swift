import RetroGuideKit
import SwiftUI

/// Options for what's on now: audio and subtitles, applied to the live picture
/// right away and remembered, each at its own scope like PASTA (this episode,
/// season, show or library), on this device, in iCloud and on the server; the
/// channel's schedule order; and why what's on is on this channel.
struct WatchOptionsPanel: View {
    private enum ChoiceID {
        static let subtitlesOff = "subtitles.off"
        static let automatic = "scope.automatic"
    }

    let tuner: Tuner
    var onPlaybackAction: (() -> Void)? = nil

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    /// Shown right away; rebuilding a large lineup takes a few seconds.
    @State private var pendingOrdering: ScheduleOrdering?
    /// Focus starts on Subtitles, the usual reason to open the panel.
    @FocusState private var isSubtitlesFocused: Bool
    @FocusState private var isReturnFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                header
                if let program = tuner.program, let channel = tuner.channel {
                    SettingsSection(String(localized: "Playback")) {
                        if tuner.isWatchingFromBeginning {
                            Text("Watching from beginning. Your channels are still following their normal schedule.")
                                .font(Typography.callout)
                                .foregroundStyle(theme.textSecondary)
                            Button("Return to Live") {
                                tuner.returnToLive()
                                closeAfterPlaybackAction()
                            }
                            .buttonStyle(.retroPrimary)
                            .focused($isReturnFocused)
                            Button("Restart from Beginning") {
                                tuner.watchFromBeginning(program, on: channel)
                                closeAfterPlaybackAction()
                            }
                            .buttonStyle(.retro)
                        } else {
                            Button("Watch from Beginning") {
                                tuner.watchFromBeginning(program, on: channel)
                                closeAfterPlaybackAction()
                            }
                            .buttonStyle(.retroPrimary)
                            Text("Start this program at 0:00. You can return to the live channel at any time.")
                                .font(Typography.callout)
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                }
                SettingsSection(String(localized: "Audio & Subtitles")) {
                    content
                }
                SleepTimerControl()
                if let channel = tuner.channel {
                    SettingsSection(String(localized: "Channel \(channel.number) · \(channel.name)")) {
                        FavoriteChannelButton(channel: channel)
                        if !app.parentalControls.needsAuthorization { scheduleOrder(for: channel) }
                        if let item = tuner.program?.item {
                            ChannelPlacementControls(channel: channel, item: item)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignTokens.Spacing.lg)
        }
        .scrollClipDisabled()
        .onAppear {
            // After the panel is on screen, so the menu can take focus.
            Task { @MainActor in
                if tuner.isWatchingFromBeginning { isReturnFocused = true }
                else { isSubtitlesFocused = true }
            }
        }
    }

    private func closeAfterPlaybackAction() {
        if let onPlaybackAction { onPlaybackAction() } else { dismiss() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack {
                Text("Options")
                    .font(Typography.title)
                    .foregroundStyle(theme.textPrimary)
                #if os(iOS)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.retro)
                #endif
            }
            if let program = tuner.program {
                Text(program.item.headline)
                    .font(Typography.bodyEmphasis)
                    .foregroundStyle(theme.accent)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !tuner.engine.switchesTracksLive {
            note(String(localized: "Choosing audio and subtitles needs the RetroGuide Player. You can switch to it in Settings › Playback › Player."))
        } else if let tracks = tuner.currentTracks, let selection = tuner.currentSelection {
            choices(tracks: tracks, selection: selection)
        } else if tuner.signal == .tuning {
            note(String(localized: "Loading this program's tracks…"))
        } else {
            note(String(localized: "This program's audio and subtitle tracks aren't available."))
        }
    }

    @ViewBuilder
    private func choices(tracks: ItemTracks, selection: TrackSelection) -> some View {
        let audio = tracks.audioOption(for: selection)
        let subtitle = tracks.subtitleOption(for: selection)
        VStack(spacing: DesignTokens.Spacing.sm) {
            OptionMenu(
                title: String(localized: "Audio", comment: "Menu of a program's audio tracks"),
                systemImage: "speaker.wave.2",
                choices: tracks.audio.map { OptionMenu.Choice(id: $0.id, title: $0.title) },
                selection: Binding(
                    get: { audio?.id ?? "" },
                    set: { id in
                        guard let option = tracks.audio.first(where: { $0.id == id }) else { return }
                        tuner.chooseAudio(option, scope: tuner.audioScope ?? defaultScope)
                    }
                )
            )
            .disabled(tracks.audio.count < 2)
            if tracks.audio.count > 1 {
                scopeMenu(title: String(localized: "Audio for", comment: "Menu: how widely the chosen audio track applies (this episode, season, show…)"), scope: tuner.audioScope) { scope in
                    if let scope, let audio {
                        tuner.chooseAudio(audio, scope: scope)
                    } else {
                        tuner.resetAudio()
                    }
                }
            }
            OptionMenu(
                title: String(localized: "Subtitles"),
                systemImage: "captions.bubble",
                choices: [OptionMenu.Choice(id: ChoiceID.subtitlesOff, title: String(localized: "Off", comment: "Subtitles turned off"))]
                    + tracks.subtitles.map { OptionMenu.Choice(id: $0.id, title: $0.title) },
                selection: Binding(
                    get: { subtitle?.id ?? ChoiceID.subtitlesOff },
                    set: { id in
                        tuner.chooseSubtitles(tracks.subtitles.first { $0.id == id }, scope: tuner.subtitleScope ?? defaultScope)
                    }
                )
            )
            .focused($isSubtitlesFocused)
            scopeMenu(title: String(localized: "Subtitles for", comment: "Menu: how widely the chosen subtitles apply (this episode, season, show…)"), scope: tuner.subtitleScope) { scope in
                if let scope {
                    tuner.chooseSubtitles(subtitle, scope: scope)
                } else {
                    tuner.resetSubtitles()
                }
            }
            if subtitle != nil, tuner.engine.adjustsSubtitleTiming {
                SubtitleTimingControl(tuner: tuner)
            }
        }
        if let progress = app.trackSync.progress {
            note(String(localized: "Saving to Plex… \(progress.done) of \(progress.total)"))
        } else if app.trackSync.failedCount > .zero {
            note(failedSaveMessage(count: app.trackSync.failedCount))
            Button("Try again", systemImage: "arrow.clockwise") {
                app.trackSync.retryFailed()
            }
            .buttonStyle(.retro)
        }
    }

    /// How far a choice reaches: "Automatic" (the server's and account's
    /// choice), or this episode, season, show or library.
    private func scopeMenu(title: String, scope: TrackScope?, onSelect: @escaping (TrackScope?) -> Void) -> some View {
        OptionMenu(
            title: title,
            systemImage: "square.stack",
            choices: [OptionMenu.Choice(id: ChoiceID.automatic, title: String(localized: "Automatic", comment: "Track choice left to the server and account defaults"))] + availableScopes.map {
                OptionMenu.Choice(id: $0.rawValue, title: scopeTitle($0))
            },
            selection: Binding(
                get: { scope?.rawValue ?? ChoiceID.automatic },
                set: { onSelect(TrackScope(rawValue: $0)) }
            )
        )
    }

    /// Scopes that mean something for what's on (movies have no seasons),
    /// the whole library with RetroGuide Pro.
    private var availableScopes: [TrackScope] {
        guard let item = tuner.program?.item else { return [] }
        let scopes: [TrackScope] = item.series == nil ? [.show, .library] : [.episode, .season, .show, .library]
        return scopes.filter { TrackRules.applies($0, to: item) && ($0 != .library || app.pro.access.canChooseTracksForLibrary) }
    }

    /// A new choice covers the whole show (or the movie) until narrowed.
    private var defaultScope: TrackScope {
        .show
    }

    private func scopeTitle(_ scope: TrackScope) -> String {
        guard let item = tuner.program?.item else { return scope.rawValue }
        switch scope {
        case .episode: return String(localized: "This episode")
        case .season: return item.series?.seasonNumber.map { String(localized: "Season \($0)") } ?? String(localized: "This season")
        case .show: return item.series.map { String(localized: "Every episode of \($0.title)") } ?? String(localized: "This movie")
        case .library:
            guard let name = libraryName(for: item) else { return String(localized: "Everything in this library") }
            return String(localized: "Everything in \(name)", comment: "Track choice scope: a whole library, by name")
        }
    }

    private func libraryName(for item: MediaItem) -> String? {
        app.libraryIndex.facets.libraries.first { $0.id == item.libraryID }?.name
    }

    /// Track choices that couldn't be saved to Plex.
    private func failedSaveMessage(count: Int) -> String {
        count == 1
            ? String(localized: "Couldn't save 1 title to Plex. Your choices are still saved on this device.")
            : String(localized: "Couldn't save \(count) titles to Plex. Your choices are still saved on this device.")
    }

    @ViewBuilder
    private func scheduleOrder(for channel: Channel) -> some View {
        let current = pendingOrdering ?? channel.definition.ordering
        OptionMenu(
            title: String(localized: "Schedule order"),
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
            note(String(localized: "Changing a channel's schedule order is part of RetroGuide Pro (Settings › RetroGuide Pro)."))
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Typography.body)
            .foregroundStyle(theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
