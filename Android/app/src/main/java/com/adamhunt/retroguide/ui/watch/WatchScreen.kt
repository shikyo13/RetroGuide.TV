package com.adamhunt.retroguide.ui.watch

import android.view.KeyEvent as AndroidKeyEvent
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.nativeKeyCode
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.DpSize
import com.adamhunt.retroguide.AppModel
import com.adamhunt.retroguide.core.ProgramInfo
import com.adamhunt.retroguide.ui.components.CornerPicture
import com.adamhunt.retroguide.ui.components.PictureWindow
import com.adamhunt.retroguide.ui.guide.GuideHeaderButton
import com.adamhunt.retroguide.ui.guide.GuideLayout
import com.adamhunt.retroguide.ui.guide.GuideModel
import com.adamhunt.retroguide.ui.guide.GuidePreviewChrome
import com.adamhunt.retroguide.ui.guide.GuideScreen
import com.adamhunt.retroguide.ui.onboarding.OnboardingScreen
import com.adamhunt.retroguide.ui.search.SearchScreen
import com.adamhunt.retroguide.ui.settings.SettingsScreen
import com.adamhunt.retroguide.ui.theme.Tokens
import kotlinx.coroutines.delay

private object WatchTiming {
    /** How long the channel banner stays up after a change or a press. */
    const val BANNER_MS = 5_000L
}

/** What covers the picture. */
private enum class Overlay { NONE, GUIDE, SEARCH, SETTINGS }

/** Live TV: the picture, channel surfing, the guide, Search and Options (the Apple app's `WatchView`). */
@Composable
fun WatchScreen(app: AppModel) {
    val tuner = app.tuner
    val channel by tuner.channel.collectAsState()
    val program by tuner.program.collectAsState()
    val signal by tuner.signal.collectAsState()
    val channels by app.channels.collectAsState()
    val isPro by app.isPro.collectAsState()
    val favoritesOnly by app.favoritesOnly.collectAsState()
    val sleepExpired by app.sleepTimer.didExpire.collectAsState()
    val addingServer by app.addingServer.collectAsState()
    val pendingReminders by app.reminders.pending.collectAsState()
    val dueReminder by app.reminders.due.collectAsState()
    val reminderMessage by app.reminders.message.collectAsState()
    val scope = rememberCoroutineScope()
    var overlay by remember { mutableStateOf(Overlay.NONE) }
    var guide by remember { mutableStateOf<GuideModel?>(null) }
    var isShowingOptions by remember { mutableStateOf(false) }
    var bannerRequest by remember { mutableIntStateOf(0) }
    var showsBanner by remember { mutableStateOf(false) }
    var showsNext by remember { mutableStateOf(false) }
    var nextProgram by remember { mutableStateOf<ProgramInfo?>(null) }
    val focus = remember { FocusRequester() }

    fun openGuide() {
        guide = GuideModel(app.core, app.browsingChannels(), channel?.id, scope)
        overlay = Overlay.GUIDE
    }

    fun closeOverlay() {
        guide = null
        overlay = Overlay.NONE
    }

    // Every channel change brings up the banner, like a TV's info bar.
    LaunchedEffect(channel?.id) { if (channel != null) bannerRequest += 1 }
    LaunchedEffect(bannerRequest) {
        if (bannerRequest == 0) return@LaunchedEffect
        showsBanner = true
        delay(WatchTiming.BANNER_MS)
        showsBanner = false
        showsNext = false
    }
    LaunchedEffect(showsNext, program?.id) {
        nextProgram = if (showsNext) program?.let { current ->
            channel?.let { runCatching { app.core.guide(current.end + 1, current.end + 2, listOf(it.id)) }.getOrNull()?.firstOrNull()?.programs?.firstOrNull() }
        } else null
    }
    // The guide follows Favorites as it's switched on and off.
    LaunchedEffect(favoritesOnly, channels) {
        if (overlay == Overlay.GUIDE) guide = GuideModel(app.core, app.browsingChannels(), channel?.id, scope)
    }
    LaunchedEffect(overlay, isShowingOptions, sleepExpired) {
        if (overlay == Overlay.SEARCH || overlay == Overlay.SETTINGS || isShowingOptions) return@LaunchedEffect
        // After the panel that had focus has left the screen.
        withFrameNanos {}
        runCatching { focus.requestFocus() }
    }

    fun pressHeaderButton(button: GuideHeaderButton) {
        when (button) {
            GuideHeaderButton.OPTIONS -> isShowingOptions = true
            GuideHeaderButton.REMINDER -> guide?.let { open ->
                val channel = open.selectedChannel
                val program = open.selectedProgram
                if (!isPro) overlay = Overlay.SETTINGS
                else if (channel != null && program != null) app.reminders.toggle(channel.id, program.id)
            }
            GuideHeaderButton.FAVORITES -> if (isPro) app.setFavoritesOnly(!favoritesOnly) else {
                guide = null
                overlay = Overlay.SETTINGS
            }
            GuideHeaderButton.SEARCH -> {
                guide = null
                overlay = Overlay.SEARCH
            }
            GuideHeaderButton.SETTINGS -> {
                guide = null
                overlay = Overlay.SETTINGS
            }
        }
    }

    fun handle(code: Int): Boolean {
        // Options and Search handle their own keys; nothing they pass up changes channel.
        if (isShowingOptions || overlay == Overlay.SEARCH || overlay == Overlay.SETTINGS || addingServer != null) return false
        if (dueReminder != null || reminderMessage != null) return false
        if (sleepExpired) {
            if (code == AndroidKeyEvent.KEYCODE_DPAD_CENTER || code == AndroidKeyEvent.KEYCODE_ENTER) {
                app.sleepTimer.resumeWatching()
                tuner.resume()
                return true
            }
            return false
        }
        if (code == AndroidKeyEvent.KEYCODE_MENU) {
            isShowingOptions = true
            return true
        }
        val open = guide
        if (open != null) {
            when (code) {
                AndroidKeyEvent.KEYCODE_DPAD_UP -> open.moveUp()
                AndroidKeyEvent.KEYCODE_DPAD_DOWN -> open.moveDown()
                AndroidKeyEvent.KEYCODE_DPAD_LEFT -> open.moveLeft()
                AndroidKeyEvent.KEYCODE_DPAD_RIGHT -> open.moveRight(open.headerButtons().size)
                AndroidKeyEvent.KEYCODE_DPAD_CENTER, AndroidKeyEvent.KEYCODE_ENTER -> when (val f = open.focus.value) {
                    is GuideModel.Focus.Header -> open.headerButtons().getOrNull(f.index)?.let(::pressHeaderButton)
                    is GuideModel.Focus.Program -> open.focusedChannel?.let {
                        tuner.tune(it)
                        closeOverlay()
                    }
                }
                AndroidKeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> open.focusHeader()
                else -> return false
            }
            return true
        }
        when (code) {
            AndroidKeyEvent.KEYCODE_DPAD_UP, AndroidKeyEvent.KEYCODE_CHANNEL_UP -> tuner.channelUp()
            AndroidKeyEvent.KEYCODE_DPAD_DOWN, AndroidKeyEvent.KEYCODE_CHANNEL_DOWN -> tuner.channelDown()
            AndroidKeyEvent.KEYCODE_DPAD_CENTER, AndroidKeyEvent.KEYCODE_ENTER, AndroidKeyEvent.KEYCODE_GUIDE -> openGuide()
            AndroidKeyEvent.KEYCODE_DPAD_LEFT -> { showsNext = false; bannerRequest += 1 }
            AndroidKeyEvent.KEYCODE_DPAD_RIGHT -> { showsNext = true; bannerRequest += 1 }
            AndroidKeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, AndroidKeyEvent.KEYCODE_LAST_CHANNEL -> tuner.recall()
            AndroidKeyEvent.KEYCODE_SEARCH -> overlay = Overlay.SEARCH
            else -> return false
        }
        return true
    }

    // Back goes to the guide's top row first, then closes it (as on Apple TV); on
    // the picture it dismisses the banner. Options and Search handle their own.
    BackHandler(enabled = guide != null && !isShowingOptions) {
        val open = guide ?: return@BackHandler
        if (open.focus.value is GuideModel.Focus.Program) open.focusHeader() else closeOverlay()
    }
    BackHandler(enabled = overlay == Overlay.NONE && showsBanner && !isShowingOptions) { showsBanner = false }

    BoxWithConstraints(
        Modifier
            .fillMaxSize()
            .focusRequester(focus)
            .focusable()
            .onKeyEvent { event -> event.type == KeyEventType.KeyDown && handle(event.key.nativeKeyCode) },
    ) {
        val screen = DpSize(maxWidth, maxHeight)
        val window = when (overlay) {
            Overlay.NONE -> PictureWindow(DpOffset(Dp(0f), Dp(0f)), screen, Dp(0f))
            Overlay.GUIDE -> GuideLayout.previewWindow
            Overlay.SEARCH, Overlay.SETTINGS -> CornerPicture.window(screen)
        }
        val motion = tween<Dp>(Tokens.Motion.RELAXED)
        val x by animateDpAsState(window.offset.x, motion, label = "videoX")
        val y by animateDpAsState(window.offset.y, motion, label = "videoY")
        val width by animateDpAsState(window.size.width, motion, label = "videoWidth")
        val height by animateDpAsState(window.size.height, motion, label = "videoHeight")

        when (overlay) {
            Overlay.GUIDE -> guide?.let { open ->
                GuideScreen(open, channel, isPro && favoritesOnly) { program ->
                    open.selectedChannel?.let { selected -> pendingReminders.any { it.channelID == selected.id && it.start == program.start } } == true
                }
            }
            Overlay.SEARCH -> SearchScreen(app, screen, onTune = { id ->
                tuner.channelWithID(id)?.let(tuner::tune)
                closeOverlay()
            }, onClose = ::closeOverlay)
            Overlay.SETTINGS -> SettingsScreen(app, screen, onClose = ::closeOverlay)
            Overlay.NONE -> Unit
        }
        Box(Modifier.offset(x, y).size(width, height)) {
            VideoSurface(app.player, Modifier.fillMaxSize())
            SignalOverlay(signal, channel, program)
            if (overlay == Overlay.GUIDE) guide?.let { GuidePreviewChrome(it, channel) }
        }
        if (overlay == Overlay.NONE) {
            val current = channel
            AnimatedVisibility(showsBanner && current != null, Modifier.align(Alignment.TopEnd).padding(Tokens.Spacing.xl), enter = fadeIn(), exit = fadeOut()) {
                current?.let { ChannelNumberOSD(it) }
            }
            AnimatedVisibility(showsBanner && current != null, Modifier.align(Alignment.BottomCenter).padding(Tokens.Spacing.xl), enter = fadeIn(), exit = fadeOut()) {
                current?.let { ChannelBanner(it, if (showsNext) nextProgram ?: program else program, isShowingNext = showsNext && nextProgram != null) }
            }
        }
        if (sleepExpired) SleepFinishedCard(Modifier.align(Alignment.Center))
        val parentalEnabled by app.parentalEnabled.collectAsState()
        if (channels.isEmpty() && parentalEnabled && overlay == Overlay.NONE) {
            NoAllowedChannelsCard(Modifier.align(Alignment.Center))
        }
        addingServer?.let { OnboardingScreen(it) }
        dueReminder?.let { reminder ->
            ReminderDueCard(reminder, Modifier.align(Alignment.Center), onWatch = {
                app.reminders.dismissDue()
                tuner.channelWithID(reminder.channelID)?.let(tuner::tune)
                closeOverlay()
            }, onDismiss = app.reminders::dismissDue)
        }
        reminderMessage?.let { text ->
            MessageCard("Reminders", text, Modifier.align(Alignment.Center), onDismiss = app.reminders::dismissMessage)
        }
        if (isShowingOptions) OptionsPanel(app, onClose = { isShowingOptions = false })
    }
}
