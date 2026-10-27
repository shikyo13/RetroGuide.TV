package com.adamhunt.retroguide.ui.watch

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.safeDrawingPadding
import com.adamhunt.retroguide.ui.LocalFormFactor
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Text
import com.adamhunt.retroguide.AppModel
import com.adamhunt.retroguide.core.Choice
import com.adamhunt.retroguide.core.OptionsInfo
import com.adamhunt.retroguide.core.SelectionInfo
import com.adamhunt.retroguide.core.TrackState
import com.adamhunt.retroguide.core.TracksInfo
import com.adamhunt.retroguide.player.SleepTimer
import com.adamhunt.retroguide.player.Signal
import com.adamhunt.retroguide.ui.components.AdjustableRow
import com.adamhunt.retroguide.ui.components.ChoiceRow
import com.adamhunt.retroguide.ui.components.Note
import com.adamhunt.retroguide.ui.components.Panel
import com.adamhunt.retroguide.ui.components.RetroButton
import com.adamhunt.retroguide.ui.components.RetroRow
import com.adamhunt.retroguide.ui.components.SectionHeader
import com.adamhunt.retroguide.ui.theme.LocalTheme
import com.adamhunt.retroguide.ui.theme.Tokens
import com.adamhunt.retroguide.ui.theme.Typography

private object OptionsLayout {
    /** The Apple TV panel's 760 points. */
    val width = 380.dp
}

private object ChoiceID {
    const val AUTOMATIC = "scope.automatic"
    const val SUBTITLES_OFF = "subtitles.off"
}

/**
 * Options for what's on (the Apple app's `WatchOptionsPanel`), beside the
 * picture: watching from the beginning; audio and subtitles, each remembered
 * at its own scope; subtitle timing; the sleep timer; and the channel's
 * favorite, schedule order and "Why is this here?".
 */
@Composable
fun OptionsPanel(app: AppModel, onClose: () -> Unit) {
    val theme = LocalTheme.current
    val tuner = app.tuner
    val channel by tuner.channel.collectAsState()
    val program by tuner.program.collectAsState()
    val tracks by tuner.tracks.collectAsState()
    val trackState by tuner.trackState.collectAsState()
    val signal by tuner.signal.collectAsState()
    val isWatchingFromBeginning by tuner.isWatchingFromBeginning.collectAsState()
    val channels by app.channels.collectAsState()
    var options by remember { mutableStateOf<OptionsInfo?>(null) }
    var revision by remember { mutableIntStateOf(0) }
    val first = remember { FocusRequester() }

    BackHandler(onBack = onClose)
    // Reload after anything that changes what the panel shows.
    LaunchedEffect(channel?.id, program?.id, channels, revision) {
        options = channel?.let { runCatching { app.core.options(it.id) }.getOrNull() }
    }
    LaunchedEffect(Unit) { runCatching { first.requestFocus() } }

    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = Tokens.Opacity.MUTED)), contentAlignment = Alignment.CenterEnd) {
        Panel(
            Modifier.safeDrawingPadding().padding(LocalFormFactor.current.margin).widthIn(max = OptionsLayout.width).fillMaxHeight(),
            color = theme.surface.copy(alpha = Tokens.Opacity.SCRIM),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.xxs)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Options", style = Typography.title, color = theme.textPrimary, modifier = Modifier.weight(1f))
                    if (LocalFormFactor.current.isTouch) RetroButton("Done", onClose)
                }
                program?.let { Text(it.headline, style = Typography.bodyEmphasis, color = theme.accent, maxLines = 2) }
            }
            LazyColumn(verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.xs)) {
                val current = program
                if (current != null && channel != null) {
                    item { SectionHeader("Playback") }
                    if (isWatchingFromBeginning) {
                        item { Note("Watching from beginning. Your channels are still following their normal schedule.") }
                        item {
                            RetroButton("Return to Live", { tuner.returnToLive(); onClose() }, Modifier.focusRequester(first), isPrimary = true)
                        }
                        item { RetroButton("Restart from Beginning", { tuner.watchFromBeginning(current); onClose() }) }
                    } else {
                        item {
                            RetroButton("Watch from Beginning", { tuner.watchFromBeginning(current); onClose() }, Modifier.focusRequester(first), isPrimary = true)
                        }
                        item { Note("Start this program at 0:00. You can return to the live channel at any time.") }
                    }
                }
                item { SectionHeader("Audio & Subtitles") }
                item { TrackChoices(app, tracks, trackState, signal, options) }
                item { SectionHeader("Sleep timer") }
                item { SleepTimerControls(app, isWatchingFromBeginning) }
                options?.let { info ->
                    item { SectionHeader(info.channelTitle) }
                    item {
                        RetroRow(if (info.isFavorite) "Remove from Favorites" else "Add to Favorites", {
                            app.toggleFavorite(info.channelID)
                            revision += 1
                        }, trailing = if (info.isFavorite) "★" else "☆")
                    }
                    item { ChannelControls(app, info) { revision += 1 } }
                }
            }
        }
    }
}

@Composable
private fun TrackChoices(app: AppModel, tracks: TracksInfo?, state: TrackState?, signal: Signal, options: OptionsInfo?) {
    val tuner = app.tuner
    Column(verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.xs)) {
        if (tracks == null) {
            Note(if (signal == Signal.Tuning) "Loading this program's tracks…" else "This program's audio and subtitle tracks aren't available.")
            return@Column
        }
        val selection = state?.selection ?: tracks.selection
        val audio = tracks.audio.firstOrNull { it.streamIndex == selection.audioStreamIndex }
        val subtitle = when (selection.subtitle) {
            SelectionInfo.EMBEDDED -> tracks.subtitles.firstOrNull { it.url == null && it.streamIndex == selection.subtitleStreamIndex }
            SelectionInfo.EXTERNAL -> tracks.subtitles.firstOrNull { it.url == selection.subtitleURL }
            else -> null
        }
        // A new choice covers the whole show (or the movie) until narrowed.
        val defaultScope = "show"
        val scopes = listOf(Choice(ChoiceID.AUTOMATIC, "Automatic")) + options?.scopes.orEmpty()
        ChoiceRow("Audio", tracks.audio.map { Choice(it.id, it.title) }, audio?.id, { tuner.chooseAudio(it.id, state?.audioScope ?: defaultScope) },
            enabled = tracks.audio.size > 1)
        if (tracks.audio.size > 1) {
            ChoiceRow("Audio for", scopes, state?.audioScope ?: ChoiceID.AUTOMATIC, { scope ->
                tuner.chooseAudio(audio?.id, scope.id.takeUnless { it == ChoiceID.AUTOMATIC })
            })
        }
        ChoiceRow(
            "Subtitles",
            listOf(Choice(ChoiceID.SUBTITLES_OFF, "Off")) + tracks.subtitles.map { Choice(it.id, it.title) },
            subtitle?.id ?: ChoiceID.SUBTITLES_OFF,
            { tuner.chooseSubtitles(it.id.takeUnless { id -> id == ChoiceID.SUBTITLES_OFF }, state?.subtitleScope ?: defaultScope) },
        )
        ChoiceRow("Subtitles for", scopes, state?.subtitleScope ?: ChoiceID.AUTOMATIC, { scope ->
            tuner.chooseSubtitles(subtitle?.id, scope.id.takeUnless { it == ChoiceID.AUTOMATIC })
        })
        if (subtitle != null && state != null) {
            AdjustableRow(
                "Subtitle timing", state.subtitleDelayText,
                onAdjust = { direction, repeatCount -> tuner.nudgeSubtitles(direction, repeatCount) },
                onSelect = { tuner.nudgeSubtitles(0, 0) },
            )
            val how = "Move subtitles later if they appear before speech, or earlier if they appear after it."
            Note(if (options?.isMovie != false) "$how Applies to this subtitle track while watching this program." else "$how The next episodes of this show start with the same timing.")
        }
    }
}

@Composable
private fun SleepTimerControls(app: AppModel, isWatchingFromBeginning: Boolean) {
    val timer = app.sleepTimer
    val deadline by timer.deadline.collectAsState()
    val program by app.tuner.program.collectAsState()
    var minutes by remember { mutableIntStateOf(SleepTimer.Choices.DEFAULT_CUSTOM_MINUTES) }
    Column(verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.xs)) {
        deadline?.let { time ->
            Note("Playback stops at ${ScheduleFormatting.time(time)}", emphasized = true)
            RetroRow("Cancel sleep timer", timer::cancel)
        }
        ChoiceRow(
            "Stop after",
            SleepTimer.Choices.PRESET_MINUTES.map { Choice(it.toString(), "$it minutes") },
            selectedID = null,
            onSelect = { timer.start(it.id.toInt()) },
        )
        AdjustableRow(
            "Custom", "$minutes minutes",
            onAdjust = { direction, _ -> minutes = (minutes + direction).coerceIn(SleepTimer.Choices.CUSTOM_MINUTES) },
            onSelect = { timer.start(minutes) },
        )
        Note("Left and Right change the minutes; Select sets the timer.")
        if (!isWatchingFromBeginning) {
            program?.let { current -> RetroRow("End of this program", { timer.startUntil(current.contentEnd) }) }
        }
        Note("Stops video and audio. Changing channels keeps the chosen stop time.")
    }
}

@Composable
private fun ChannelControls(app: AppModel, info: OptionsInfo, onChange: () -> Unit) {
    var pendingOrdering by remember(info.channelID) { mutableStateOf<String?>(null) }
    var isExplaining by remember(info.showID) { mutableStateOf(false) }
    var isConfirmingRemoval by remember(info.showID) { mutableStateOf(false) }
    var removed by remember(info.channelID) { mutableStateOf<Pair<String, String>?>(null) }
    val channelName = info.channelTitle.substringAfter(" · ")
    Column(verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.xs)) {
        val ordering = pendingOrdering ?: info.ordering
        ChoiceRow("Schedule order", info.orderings, ordering, { choice ->
            pendingOrdering = choice.id
            app.setOrdering(info.channelID, choice.id)
        }, enabled = info.canChangeOrdering)
        if (info.canChangeOrdering) {
            Note(info.orderings.firstOrNull { it.id == ordering }?.let { if (it.id == info.ordering) info.orderingExplanation else "Updating the schedule…" } ?: info.orderingExplanation)
        } else {
            Note("Changing a channel's schedule order is part of RetroGuide Pro (Settings › RetroGuide Pro).")
        }
        RetroRow("Why is this here?", { isExplaining = !isExplaining }, trailing = if (isExplaining) "▴" else "▾")
        if (isExplaining) Note(info.placement)
        removed?.let { (showID, name) ->
            Note("$name is removed from $channelName. Settings › Channels › Removed from channels lists everything you've removed.")
            RetroRow("Undo: put $name back", {
                app.restoreTitle(info.channelID, showID)
                removed = null
                onChange()
            })
        }
        if (info.isRemovable) {
            val noun = if (info.isMovie) "movie" else "show"
            when {
                !info.canRemove -> Note("Removing a show from a channel is part of RetroGuide Pro (Settings › RetroGuide Pro).")
                isConfirmingRemoval -> {
                    Note("Remove ${app.tuner.program.value?.headline ?: "it"} from $channelName? It stays on your other channels. You can put it back any time in Settings › Channels › Removed from channels.")
                    RetroRow("Remove", {
                        removed = info.showID to (app.tuner.program.value?.headline ?: "")
                        isConfirmingRemoval = false
                        app.removeTitle(info.channelID, info.showID)
                        onChange()
                    })
                    RetroRow("Cancel", { isConfirmingRemoval = false })
                }
                else -> RetroRow("Remove this $noun from this channel", { isConfirmingRemoval = true })
            }
        }
    }
    // The schedule settles once the rebuilt lineup carries the new order.
    LaunchedEffect(info.ordering) { if (info.ordering == pendingOrdering) pendingOrdering = null }
}
