package com.adamhunt.retroguide.ui.settings

import androidx.activity.compose.BackHandler
import com.adamhunt.retroguide.ui.components.RetroButton
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.safeDrawingPadding
import com.adamhunt.retroguide.ui.LocalFormFactor
import kotlinx.coroutines.launch
import com.adamhunt.retroguide.ui.theme.Tokens
import com.adamhunt.retroguide.core.HomeRowSettings
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Text
import com.adamhunt.retroguide.AppModel
import com.adamhunt.retroguide.BuildConfig
import com.adamhunt.retroguide.core.ChannelDraft
import com.adamhunt.retroguide.core.LineupSettings
import com.adamhunt.retroguide.ui.components.CornerPicture
import com.adamhunt.retroguide.ui.components.Note
import com.adamhunt.retroguide.ui.components.ProLockedRow
import com.adamhunt.retroguide.ui.components.PRO_BADGE
import com.adamhunt.retroguide.ui.components.RetroRow
import com.adamhunt.retroguide.ui.components.SectionHeader
import com.adamhunt.retroguide.ui.components.screenBackground
import com.adamhunt.retroguide.ui.components.LocalShowsScanlines
import com.adamhunt.retroguide.ui.components.crtEffect
import com.adamhunt.retroguide.ui.theme.LocalTheme
import com.adamhunt.retroguide.ui.theme.ThemePalettes
import com.adamhunt.retroguide.ui.theme.Typography

/** Sizes of Settings (the Apple app's settings column, halved for Android TV's dp grid). */
object SettingsLayout {
    val top = 24.dp
    val columnWidth = 560.dp
}

/** A page of Settings. */
sealed interface SettingsRoute {
    data object Main : SettingsRoute
    data object Pro : SettingsRoute
    data object Themes : SettingsRoute
    data object Favorites : SettingsRoute
    data object Channels : SettingsRoute
    data class Channel(val id: String) : SettingsRoute
    data object ChannelGroups : SettingsRoute
    data object ChannelsPerShow : SettingsRoute
    data object RemovedTitles : SettingsRoute
    data object ScheduleOrder : SettingsRoute
    data object StartTimes : SettingsRoute
    data class ChannelEditor(val draft: ChannelDraft) : SettingsRoute
    data object Servers : SettingsRoute
    data class Server(val id: String) : SettingsRoute
    data object Acknowledgements : SettingsRoute
    data object ParentalControls : SettingsRoute
    data object Reminders : SettingsRoute
    data object MatchTVMode : SettingsRoute
}

/** Moves between Settings pages, remembering where each open page was scrolled. */
class SettingsNavigator(private val onClose: () -> Unit) {
    /** Where a page was when the viewer went deeper. */
    data class Position(val firstVisible: Int)

    val stack = mutableStateListOf<SettingsRoute>(SettingsRoute.Main)
    val current get() = stack.last()
    private val positions = mutableMapOf<Int, Position>()

    fun open(route: SettingsRoute) {
        stack.add(route)
    }

    fun back() {
        positions.remove(stack.lastIndex)
        if (stack.size > 1) stack.removeAt(stack.lastIndex) else onClose()
    }

    fun remembered(): Position? = positions[stack.lastIndex]

    fun remember(firstVisible: Int) {
        positions[stack.lastIndex] = Position(firstVisible)
    }
}

/**
 * Settings, over live TV (which keeps playing in the corner): the Apple app's
 * `SettingsView` and the pages it opens.
 */
@Composable
fun SettingsScreen(app: AppModel, screen: DpSize, onClose: () -> Unit) {
    val theme = LocalTheme.current
    val navigator = remember { SettingsNavigator(onClose) }
    val parentalEnabled by app.parentalEnabled.collectAsState()
    val isAuthorized by app.parentalLock.isAuthorized.collectAsState()
    // Closing Settings locks them again.
    DisposableEffect(Unit) { onDispose { app.endParentalAuthorization() } }
    BackHandler(onBack = navigator::back)
    val formFactor = LocalFormFactor.current
    val picture = CornerPicture.window(screen, formFactor.margin)
    Box(
        Modifier.fillMaxSize()
            .screenBackground(theme, picture)
            .crtEffect(LocalShowsScanlines.current, picture),
    ) {
        Column(
            Modifier
                .safeDrawingPadding()
                .padding(start = formFactor.margin, end = formFactor.margin, top = if (formFactor.isTouch) 0.dp else SettingsLayout.top)
                .padding(CornerPicture.clearance(screen, formFactor.margin).takeIf { formFactor.isTouch } ?: PaddingValues())
                .widthIn(max = SettingsLayout.columnWidth),
        ) {
            if (formFactor.isTouch) RetroButton("‹ Back", navigator::back)
            Box {
            if (app.parentalLock.isUnavailable || (parentalEnabled && !isAuthorized)) {
                ParentalPinPage(app, onCancel = onClose)
                return@Box
            }
            when (val route = navigator.current) {
                SettingsRoute.Main -> MainPage(app, navigator)
                SettingsRoute.Pro -> ProPage(app)
                SettingsRoute.Themes -> ThemesPage(app, navigator)
                SettingsRoute.Favorites -> FavoritesPage(app, navigator)
                SettingsRoute.Channels -> ManageChannelsPage(app, navigator)
                is SettingsRoute.Channel -> ChannelDetailPage(app, navigator, route.id)
                SettingsRoute.ChannelGroups -> ChannelGroupsPage(app)
                SettingsRoute.ChannelsPerShow -> ChannelsPerShowPage(app)
                SettingsRoute.RemovedTitles -> RemovedTitlesPage(app)
                SettingsRoute.ScheduleOrder -> ScheduleOrderPage(app)
                SettingsRoute.StartTimes -> StartTimesPage(app)
                is SettingsRoute.ChannelEditor -> ChannelEditorPage(app, navigator, route.draft)
                SettingsRoute.Servers -> ServersPage(app, navigator)
                is SettingsRoute.Server -> ServerPage(app, navigator, route.id)
                SettingsRoute.Acknowledgements -> AcknowledgementsPage()
                SettingsRoute.ParentalControls -> ParentalControlsPage(app, navigator)
                SettingsRoute.Reminders -> RemindersPage(app, navigator)
                SettingsRoute.MatchTVMode -> MatchTVModePage(app)
            }
            }
        }
    }
}

@Composable
private fun MainPage(app: AppModel, navigator: SettingsNavigator) {
    val theme = LocalTheme.current
    val servers by app.servers.collectAsState()
    val themeID by app.themeID.collectAsState()
    val isPro by app.isPro.collectAsState()
    val revision by app.lineupRevision.collectAsState()
    val isRefreshing by app.isRefreshing.collectAsState()
    var lineup by remember { mutableStateOf<LineupSettings?>(null) }
    var isConfirmingSignOut by remember { mutableStateOf(false) }
    LaunchedEffect(revision, isPro) { lineup = runCatching { app.core.lineupSettings() }.getOrNull() }
    SettingsPage("Settings", navigator) {
        item { SectionHeader("RetroGuide Pro") }
        item { RetroRow(if (isPro) "RetroGuide Pro" else "Upgrade to Pro", { navigator.open(SettingsRoute.Pro) }, trailing = if (isPro) "Active" else PRO_BADGE) }

        item { SectionHeader("Picture") }
        // Android TV's home screen; phones and tablets get the What's On widget instead.
        if (!app.formFactor.isTouch) item { HomeRowSetting(app, navigator, isPro) }
        item { RetroRow("Theme", { navigator.open(SettingsRoute.Themes) }, trailing = ThemePalettes.first { it.id == themeID }.name) }
        item {
            val showsScanlines by app.showsScanlines.collectAsState()
            RetroRow("Scanlines on menus", { app.setShowsScanlines(!showsScanlines) }, trailing = if (showsScanlines) "On" else "Off")
        }

        item { SectionHeader("Playback") }
        item { RetroRow("Program reminders", { navigator.open(SettingsRoute.Reminders) }, trailing = if (isPro) null else PRO_BADGE) }
        if (!app.formFactor.isTouch) {
            item {
                val matchTVMode by app.matchTVMode.collectAsState()
                RetroRow("Match TV mode", { navigator.open(SettingsRoute.MatchTVMode) }, trailing = matchTVMode.title)
            }
        }

        item { SectionHeader("Channels") }
        item {
            RetroRow("Favorites", { navigator.open(SettingsRoute.Favorites) },
                trailing = if (isPro) "${lineup?.favoriteCount ?: 0}" else PRO_BADGE)
        }
        item {
            val summary = lineup?.let { if (it.hiddenCount > 0) "${it.channelCount} channels, ${it.hiddenCount} hidden" else "${it.channelCount} channels" }
            RetroRow("Manage channels", { navigator.open(SettingsRoute.Channels) }, trailing = summary)
        }
        item { RetroRow("Channel groups", { navigator.open(SettingsRoute.ChannelGroups) }) }
        item {
            RetroRow("Channels per show", { navigator.open(SettingsRoute.ChannelsPerShow) },
                trailing = lineup?.let { settings -> settings.simulcastLimits.firstOrNull { it.id == settings.simulcastLimit }?.title })
        }
        lineup?.takeIf { it.removedTitleCount > 0 }?.let { settings ->
            item { RetroRow("Removed from channels", { navigator.open(SettingsRoute.RemovedTitles) }, trailing = "${settings.removedTitleCount}") }
        }
        item {
            if (lineup?.canCreateCustomChannel == true) {
                RetroRow("Create a channel", { navigator.open(SettingsRoute.ChannelEditor(ChannelDraft())) })
            } else {
                ProLockedRow("Create another channel", { navigator.open(SettingsRoute.Pro) })
            }
        }
        item {
            if (lineup?.canChangeScheduling == true) {
                RetroRow("Schedule order", { navigator.open(SettingsRoute.ScheduleOrder) },
                    trailing = lineup?.let { settings -> settings.orderings.firstOrNull { it.id == settings.defaultOrdering }?.title ?: "Per channel" })
            } else {
                ProLockedRow("Schedule order", { navigator.open(SettingsRoute.Pro) })
            }
        }
        item {
            if (lineup?.canChangeScheduling == true) {
                RetroRow("Program start times", { navigator.open(SettingsRoute.StartTimes) },
                    trailing = lineup?.let { settings -> settings.scheduleGrids.firstOrNull { it.id == settings.scheduleGrid }?.title })
            } else {
                ProLockedRow("Program start times", { navigator.open(SettingsRoute.Pro) })
            }
        }

        item { SectionHeader("Library") }
        item {
            RetroRow("Servers", { navigator.open(SettingsRoute.Servers) },
                trailing = if (servers.size == 1) servers.first().name else "${servers.size} servers")
        }
        item { RetroRow("Refresh library", { if (!isRefreshing) app.refresh(showsProgress = false) }, trailing = if (isRefreshing) "Refreshing…" else null) }

        item { SectionHeader("Account and Security") }
        item {
            val parentalEnabled by app.parentalEnabled.collectAsState()
            RetroRow("Parental Controls", { navigator.open(SettingsRoute.ParentalControls) }, trailing = if (parentalEnabled) "On" else "Off")
        }
        item {
            if (isConfirmingSignOut) {
                Note("Sign out and remove all channels from this device?")
            } else {
                RetroRow("Sign out", { isConfirmingSignOut = true })
            }
        }
        if (isConfirmingSignOut) {
            item { RetroRow("Sign Out", app::signOut) }
            item { RetroRow("Cancel", { isConfirmingSignOut = false }) }
        }

        item { SectionHeader("About") }
        item { RetroRow("Acknowledgements", { navigator.open(SettingsRoute.Acknowledgements) }) }
        item {
            Text("RetroGuide.TV ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE}) · Open source under the MIT License",
                style = Typography.caption, color = theme.textSecondary, modifier = Modifier.padding(top = SettingsLayout.top))
        }
    }
}

/** Which channels the TV's home screen row shows (the Apple app's Top Shelf setting). */
@Composable
private fun HomeRowSetting(app: AppModel, navigator: SettingsNavigator, isPro: Boolean) {
    val scope = rememberCoroutineScope()
    var settings by remember { mutableStateOf<HomeRowSettings?>(null) }
    LaunchedEffect(Unit) { settings = runCatching { app.core.homeRowSettings() }.getOrNull() }
    val usesFavorites = isPro && settings?.usesFavorites == true
    Column(verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.xs)) {
        if (isPro) {
            RetroRow("Home screen row", {
                scope.launch {
                    settings = runCatching { app.core.setHomeRowFavorites(!usesFavorites) }.getOrNull()
                    app.updateHomeRow()
                }
            }, trailing = if (usesFavorites) "Favorites" else "Recent channels")
        } else {
            RetroRow("Home screen row", {}, trailing = "Recent channels")
            ProLockedRow("Use Favorites on the home screen", { navigator.open(SettingsRoute.Pro) })
        }
        if (usesFavorites && settings?.hasFavorites == false) {
            Note("No favorite channels are available. Add channels in Favorites below to show them on the home screen.")
        }
        Note("Android TV home screens that show app rows list what's on in \u201CWhat's On\u201D.")
    }
}
