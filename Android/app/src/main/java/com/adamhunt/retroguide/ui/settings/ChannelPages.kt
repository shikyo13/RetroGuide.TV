package com.adamhunt.retroguide.ui.settings

import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.adamhunt.retroguide.AppModel
import com.adamhunt.retroguide.core.ChannelDetail
import com.adamhunt.retroguide.core.ChannelSummary
import com.adamhunt.retroguide.core.LineupSettings
import com.adamhunt.retroguide.core.RemovedGroup
import com.adamhunt.retroguide.ui.components.CheckmarkRow
import com.adamhunt.retroguide.ui.components.Note
import com.adamhunt.retroguide.ui.components.ProLockedRow
import com.adamhunt.retroguide.ui.components.PRO_BADGE
import com.adamhunt.retroguide.ui.components.RetroRow
import com.adamhunt.retroguide.ui.components.RetroTextField
import com.adamhunt.retroguide.ui.components.SectionHeader
import com.adamhunt.retroguide.ui.theme.ThemePalettes
import androidx.compose.ui.text.input.KeyboardType

/** Lineup-wide settings, reloaded after every lineup change. */
@Composable
internal fun rememberLineupSettings(app: AppModel): LineupSettings? {
    val revision by app.lineupRevision.collectAsState()
    val isPro by app.isPro.collectAsState()
    var settings by remember { mutableStateOf<LineupSettings?>(null) }
    LaunchedEffect(revision, isPro) { settings = runCatching { app.core.lineupSettings() }.getOrNull() }
    return settings
}

/** Every channel, hidden ones too, reloaded after every lineup change. */
@Composable
private fun rememberChannels(app: AppModel): List<ChannelSummary> {
    val revision by app.lineupRevision.collectAsState()
    var channels by remember { mutableStateOf<List<ChannelSummary>>(emptyList()) }
    LaunchedEffect(revision) { channels = runCatching { app.core.manageChannels() }.getOrDefault(emptyList()) }
    return channels
}

@Composable
fun ThemesPage(app: AppModel, navigator: SettingsNavigator) {
    val themeID by app.themeID.collectAsState()
    val isPro by app.isPro.collectAsState()
    SettingsPage("Theme") {
        items(ThemePalettes, key = { it.id }) { palette ->
            val isLocked = !palette.id.isIncludedFree && !isPro
            RetroRow(
                palette.name,
                onClick = { if (isLocked) navigator.open(SettingsRoute.Pro) else app.setTheme(palette.id) },
                trailing = when {
                    palette.id == themeID -> "✓"
                    isLocked -> PRO_BADGE
                    else -> ""
                },
            )
        }
    }
}

/** Starred channels, and whether the guide and surfing show only them (the Apple app's `FavoritesView`). */
@Composable
fun FavoritesPage(app: AppModel, navigator: SettingsNavigator) {
    val isPro by app.isPro.collectAsState()
    val favoritesOnly by app.favoritesOnly.collectAsState()
    val channels = rememberChannels(app)
    var query by remember { mutableStateOf("") }
    val matching = channels.filter {
        val search = query.trim()
        search.isEmpty() || it.name.contains(search, ignoreCase = true) || it.number.toString() == search
    }
    SettingsPage("Favorites", navigator) {
        if (!isPro) {
            item { Note("Favorites let the guide and channel surfing show just the channels you choose.") }
            item { ProLockedRow("Choose favorite channels", { navigator.open(SettingsRoute.Pro) }) }
            return@SettingsPage
        }
        item { SectionHeader("Browsing") }
        item {
            RetroRow("Guide & channel surfing", { app.setFavoritesOnly(!favoritesOnly) },
                trailing = if (favoritesOnly) "Favorites" else "All channels")
        }
        item { Note("Star channels below. Hidden and unavailable channels stay saved and return when available.") }
        item { RetroTextField(query, { query = it }, "Find a channel", Modifier, KeyboardType.Text) {} }
        item { SectionHeader("Channels") }
        if (matching.isEmpty()) {
            item { Note(if (query.isEmpty()) "No channels are available yet." else "No matching channels") }
        }
        items(matching, key = { it.id }) { channel ->
            RetroRow("${channel.number} · ${channel.name}", { app.toggleFavorite(channel.id) },
                trailing = if (channel.isFavorite) "★ Favorite" else "☆ Add favorite")
        }
    }
}

/** Every channel in the lineup, grouped by where it came from (the Apple app's `ChannelManagerView`). */
@Composable
fun ManageChannelsPage(app: AppModel, navigator: SettingsNavigator) {
    val channels = rememberChannels(app)
    SettingsPage("Channels", navigator) {
        for ((sourceName, group) in channels.groupBy { it.sourceName }) {
            item(key = "header-$sourceName") { SectionHeader(sourceName) }
            items(group, key = { it.id }) { channel ->
                RetroRow(
                    "${channel.number}  ${channel.name}",
                    { navigator.open(SettingsRoute.Channel(channel.id)) },
                    detail = channel.size,
                    trailing = if (channel.isHidden) "Hidden" else "",
                )
            }
        }
    }
}

/** One channel's visibility, schedule order and removed titles (the Apple app's `ChannelDetailView`). */
@Composable
fun ChannelDetailPage(app: AppModel, navigator: SettingsNavigator, channelID: String) {
    val revision by app.lineupRevision.collectAsState()
    val isPro by app.isPro.collectAsState()
    var detail by remember { mutableStateOf<ChannelDetail?>(null) }
    var isMissing by remember { mutableStateOf(false) }
    val settings = rememberLineupSettings(app)
    LaunchedEffect(revision, channelID) {
        val loaded = runCatching { app.core.channelDetail(channelID) }.getOrNull()
        detail = loaded
        isMissing = loaded == null
    }
    val current = detail
    if (current == null) {
        SettingsPage("Channel") {
            if (isMissing) item { Note("This channel no longer has any programs.") }
        }
        return
    }
    val channel = current.channel
    SettingsPage("${channel.number}  ${channel.name}", navigator) {
        item { Note("${channel.size}\nFeaturing ${current.featuring.joinToString(", ")}") }
        item { SectionHeader("Guide") }
        item {
            if (isPro) {
                RetroRow("${channel.number} · ${channel.name}", { app.toggleFavorite(channel.id) },
                    trailing = if (channel.isFavorite) "★ Favorite" else "☆ Add favorite")
            } else {
                ProLockedRow("Add to Favorites", { navigator.open(SettingsRoute.Pro) })
            }
        }
        item { RetroRow("Show in guide", { app.setHidden(channel.id, !channel.isHidden) }, trailing = if (channel.isHidden) "Hidden" else "Shown") }
        item { SectionHeader("Schedule order") }
        val orderings = settings?.orderings.orEmpty()
        if (settings?.canChangeScheduling == true) {
            items(orderings, key = { "order-${it.id}" }) { ordering ->
                CheckmarkRow(ordering.title, current.ordering == ordering.id, { app.setOrdering(channel.id, ordering.id) }, detail = ordering.detail)
            }
        } else {
            orderings.firstOrNull { it.id == current.ordering }?.let { ordering ->
                item { CheckmarkRow(ordering.title, true, {}, detail = ordering.detail) }
            }
            item { ProLockedRow("Change schedule order", { navigator.open(SettingsRoute.Pro) }) }
        }
        if (current.removedTitles.isNotEmpty()) {
            item { SectionHeader("Removed from this channel") }
            items(current.removedTitles, key = { "removed-${it.showID}" }) { title ->
                RetroRow(title.name, { app.restoreTitle(channel.id, title.showID) }, trailing = "Put back")
            }
        }
        current.draft?.let { draft ->
            item { SectionHeader("Custom channel") }
            item { RetroRow("Edit channel", { navigator.open(SettingsRoute.ChannelEditor(draft)) }) }
            item {
                RetroRow("Delete channel", {
                    app.deleteCustomChannel(channel.id)
                    navigator.back()
                })
            }
        }
    }
}

/** Turns whole groups of automatic channels on or off (the Apple app's `ChannelGroupsView`). */
@Composable
fun ChannelGroupsPage(app: AppModel) {
    val settings = rememberLineupSettings(app)
    SettingsPage("Channel Groups") {
        item { Note("Choose which kinds of channels are built automatically from your library. Your own channels are always kept.") }
        items(settings?.groups.orEmpty(), key = { it.id }) { group ->
            CheckmarkRow(group.name, group.isEnabled, { app.setSource(group.id, !group.isEnabled) },
                detail = if (group.channelCount == 1) "1 channel" else "${group.channelCount} channels")
        }
    }
}

/** How many channels may air the same show at once (the Apple app's `SimulcastLimitPickerView`). */
@Composable
fun ChannelsPerShowPage(app: AppModel) {
    val settings = rememberLineupSettings(app)
    var pending by remember { mutableStateOf<String?>(null) }
    val current = pending ?: settings?.simulcastLimit
    LaunchedEffect(settings?.simulcastLimit) { if (settings?.simulcastLimit == pending) pending = null }
    SettingsPage("Channels per Show") {
        settings?.simulcastLimits?.firstOrNull { it.id == current }?.let { item { Note(it.detail) } }
        item { Note("Applies to automatic channels. 24/7 and custom channels are excluded from this limit. If no other show can fill a slot, the limit may be exceeded.") }
        item { Note("The scheduler also avoids airing the exact same episode or movie on multiple channels when alternatives are available.") }
        items(settings?.simulcastLimits.orEmpty(), key = { it.id }) { limit ->
            CheckmarkRow(limit.title, current == limit.id, {
                pending = limit.id
                app.setSimulcastLimit(limit.id)
            })
        }
        if (pending != null) item { Note("Updating the schedule…") }
    }
}

/** Every show and movie removed from a channel, with a way to put it back (the Apple app's `RemovedTitlesPage`). */
@Composable
fun RemovedTitlesPage(app: AppModel) {
    val revision by app.lineupRevision.collectAsState()
    var groups by remember { mutableStateOf<List<RemovedGroup>>(emptyList()) }
    LaunchedEffect(revision) { groups = runCatching { app.core.removedTitles() }.getOrDefault(emptyList()) }
    SettingsPage("Removed from channels") {
        if (groups.isEmpty()) {
            item { Note("Nothing is removed from any channel. To remove a show from one, open Options while it's on and choose Remove this show from this channel.") }
        }
        for (group in groups) {
            item(key = "header-${group.channelID}") { SectionHeader(group.channelName) }
            items(group.titles, key = { "${group.channelID}-${it.showID}" }) { title ->
                RetroRow(title.name, { app.restoreTitle(group.channelID, title.showID) }, trailing = "Put back")
            }
        }
    }
}

/** One schedule order for every channel at once (the Apple app's `AllChannelsOrderView`). */
@Composable
fun ScheduleOrderPage(app: AppModel) {
    val settings = rememberLineupSettings(app)
    SettingsPage("Schedule Order") {
        item {
            Note("Set the program order for the current lineup. You can change individual channels in Manage channels. Choosing Each channel's own restores automatic-channel defaults and keeps custom-channel orders.")
        }
        item {
            CheckmarkRow("Each channel's own", settings != null && settings.defaultOrdering == null, { app.setOrderingForAllChannels(null) },
                detail = "Restore automatic-channel defaults. Keep custom-channel orders.")
        }
        items(settings?.orderings.orEmpty(), key = { it.id }) { ordering ->
            CheckmarkRow(ordering.title, settings?.defaultOrdering == ordering.id, { app.setOrderingForAllChannels(ordering.id) }, detail = ordering.detail)
        }
    }
}

/** Back to back, or starting on the hour and half hour (the Apple app's `ScheduleGridPickerView`). */
@Composable
fun StartTimesPage(app: AppModel) {
    val settings = rememberLineupSettings(app)
    SettingsPage("Program Start Times") {
        item {
            Note("Real TV starts shows on the hour and half hour. Aligning to a grid adds a short “We'll be right back” break between programs so the guide lines up neatly.")
        }
        items(settings?.scheduleGrids.orEmpty(), key = { it.id }) { grid ->
            CheckmarkRow(grid.title, settings?.scheduleGrid == grid.id, { app.setScheduleGrid(grid.id) })
        }
    }
}
