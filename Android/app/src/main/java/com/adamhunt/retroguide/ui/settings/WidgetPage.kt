package com.adamhunt.retroguide.ui.settings

import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import com.adamhunt.retroguide.AppModel
import com.adamhunt.retroguide.core.WidgetSettings
import com.adamhunt.retroguide.ui.components.CheckmarkRow
import com.adamhunt.retroguide.ui.components.Note
import com.adamhunt.retroguide.ui.components.ProLockedRow
import com.adamhunt.retroguide.ui.components.RetroRow
import com.adamhunt.retroguide.ui.components.SectionHeader
import kotlinx.coroutines.launch

/** `ViewingPreferences.WidgetSource` raw values the page branches on. */
private object WidgetSource {
    const val FAVORITES = "favorites"
    const val SELECTED = "selected"
    const val PINNED = "pinned"
}

/** Which channels the What's On widget shows (the Apple app's `WidgetSettingsView`). */
@Composable
fun WidgetPage(app: AppModel, navigator: SettingsNavigator) {
    val scope = rememberCoroutineScope()
    val isPro by app.isPro.collectAsState()
    val channels by app.channels.collectAsState()
    var settings by remember { mutableStateOf<WidgetSettings?>(null) }
    LaunchedEffect(Unit) { settings = runCatching { app.core.widgetSettings() }.getOrNull() }
    fun change(request: suspend () -> WidgetSettings) {
        scope.launch {
            settings = runCatching { request() }.getOrNull() ?: settings
            app.updateHomeRow()
        }
    }
    SettingsPage("Home Screen", navigator) {
        item { Note("Add What's On for artwork, what's on now and channel controls. It follows your app theme.") }
        item { Note("Touch and hold your home screen, choose Widgets, then find RetroGuide.TV. Open the app to refresh the saved schedule.") }
        val current = settings ?: return@SettingsPage
        if (!isPro) {
            item { ProLockedRow("Customize widget channels", { navigator.open(SettingsRoute.Pro) }) }
            return@SettingsPage
        }
        item { SectionHeader("What's On channels") }
        items(current.sources, key = { it.id }) { source ->
            CheckmarkRow(source.title, current.source == source.id, { change { app.core.setWidgetSource(source.id) } })
        }
        if (current.source == WidgetSource.FAVORITES) {
            if (!current.hasFavorites) item { Note("No favorite channels are available. Choose Favorites below to add channels to your widget.") }
            item { RetroRow("Choose Favorites", { navigator.open(SettingsRoute.Favorites) }) }
        }
        if (current.source == WidgetSource.SELECTED || current.source == WidgetSource.PINNED) {
            val isPinned = current.source == WidgetSource.PINNED
            fun isChosen(id: String) = if (isPinned) current.pinnedID == id else id in current.selectedIDs
            item { Note(if (isPinned) "Pin one channel to stop automatic rotation." else "Choose up to ${current.limit} channels.") }
            if (channels.none { isChosen(it.id) }) item { Note("Choose a channel below to show programs in your widget.") }
            item { SectionHeader("Channels") }
            items(channels, key = { "channel-${it.id}" }) { channel ->
                CheckmarkRow("${channel.number} · ${channel.name}", isChosen(channel.id), {
                    val isFull = !isPinned && !isChosen(channel.id) && current.selectedIDs.size >= current.limit
                    if (!isFull) change { app.core.toggleWidgetChannel(channel.id) }
                })
            }
        }
    }
}
