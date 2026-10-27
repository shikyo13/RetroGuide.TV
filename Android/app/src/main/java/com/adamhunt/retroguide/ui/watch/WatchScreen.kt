package com.adamhunt.retroguide.ui.watch

import android.view.KeyEvent as AndroidKeyEvent
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.nativeKeyCode
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.key.key
import com.adamhunt.retroguide.AppModel
import com.adamhunt.retroguide.core.ProgramInfo
import com.adamhunt.retroguide.ui.guide.GuideHeaderButton
import com.adamhunt.retroguide.ui.guide.GuideLayout
import com.adamhunt.retroguide.ui.guide.GuideModel
import com.adamhunt.retroguide.ui.guide.GuideScreen
import com.adamhunt.retroguide.ui.theme.Tokens
import kotlinx.coroutines.delay

private object WatchTiming {
    /** How long the channel banner stays up after a change or a press. */
    const val BANNER_MS = 5_000L
}

/** Live TV: the picture, channel surfing and the guide (the Apple app's `WatchView`). */
@Composable
fun WatchScreen(app: AppModel, onOpenSettings: () -> Unit) {
    val tuner = app.tuner
    val channel by tuner.channel.collectAsState()
    val program by tuner.program.collectAsState()
    val signal by tuner.signal.collectAsState()
    val channels by app.channels.collectAsState()
    val scope = rememberCoroutineScope()
    var guide by remember { mutableStateOf<GuideModel?>(null) }
    var bannerRequest by remember { mutableIntStateOf(0) }
    var showsBanner by remember { mutableStateOf(false) }
    var showsNext by remember { mutableStateOf(false) }
    var nextProgram by remember { mutableStateOf<ProgramInfo?>(null) }
    val focus = remember { FocusRequester() }

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
    LaunchedEffect(guide) { runCatching { focus.requestFocus() } }

    fun handle(code: Int): Boolean {
        val open = guide
        if (open != null) {
            when (code) {
                AndroidKeyEvent.KEYCODE_DPAD_UP -> open.moveUp()
                AndroidKeyEvent.KEYCODE_DPAD_DOWN -> open.moveDown()
                AndroidKeyEvent.KEYCODE_DPAD_LEFT -> open.moveLeft()
                AndroidKeyEvent.KEYCODE_DPAD_RIGHT -> open.moveRight(GuideHeaderButton.entries.size)
                AndroidKeyEvent.KEYCODE_DPAD_CENTER, AndroidKeyEvent.KEYCODE_ENTER -> when (val f = open.focus.value) {
                    is GuideModel.Focus.Header -> if (GuideHeaderButton.entries[f.index] == GuideHeaderButton.SETTINGS) {
                        guide = null
                        onOpenSettings()
                    }
                    is GuideModel.Focus.Program -> open.focusedChannel?.let {
                        tuner.tune(it)
                        guide = null
                    }
                }
                AndroidKeyEvent.KEYCODE_BACK, AndroidKeyEvent.KEYCODE_ESCAPE -> guide = null
                AndroidKeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> open.focusHeader()
                else -> return false
            }
            return true
        }
        when (code) {
            AndroidKeyEvent.KEYCODE_DPAD_UP, AndroidKeyEvent.KEYCODE_CHANNEL_UP -> tuner.channelUp()
            AndroidKeyEvent.KEYCODE_DPAD_DOWN, AndroidKeyEvent.KEYCODE_CHANNEL_DOWN -> tuner.channelDown()
            AndroidKeyEvent.KEYCODE_DPAD_CENTER, AndroidKeyEvent.KEYCODE_ENTER, AndroidKeyEvent.KEYCODE_GUIDE ->
                guide = GuideModel(app.core, channels, channel?.id, scope)
            AndroidKeyEvent.KEYCODE_DPAD_LEFT -> { showsNext = false; bannerRequest += 1 }
            AndroidKeyEvent.KEYCODE_DPAD_RIGHT -> { showsNext = true; bannerRequest += 1 }
            AndroidKeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, AndroidKeyEvent.KEYCODE_LAST_CHANNEL -> tuner.recall()
            AndroidKeyEvent.KEYCODE_BACK, AndroidKeyEvent.KEYCODE_ESCAPE -> if (showsBanner) showsBanner = false else return false
            else -> return false
        }
        return true
    }

    BoxWithConstraints(
        Modifier
            .fillMaxSize()
            .focusRequester(focus)
            .focusable()
            .onKeyEvent { event -> event.type == KeyEventType.KeyDown && handle(event.key.nativeKeyCode) },
    ) {
        val isGuideOpen = guide != null
        val motion = tween<androidx.compose.ui.unit.Dp>(Tokens.Motion.RELAXED)
        val x by animateDpAsState(if (isGuideOpen) GuideLayout.margin else androidx.compose.ui.unit.Dp(0f), motion, label = "videoX")
        val y by animateDpAsState(if (isGuideOpen) GuideLayout.previewTop else androidx.compose.ui.unit.Dp(0f), motion, label = "videoY")
        val width by animateDpAsState(if (isGuideOpen) GuideLayout.previewWidth else maxWidth, motion, label = "videoWidth")
        val height by animateDpAsState(if (isGuideOpen) GuideLayout.previewHeight else maxHeight, motion, label = "videoHeight")

        guide?.let { GuideScreen(it, channel) }
        Box(Modifier.offset(x, y).size(width, height)) {
            VideoSurface(app.player, Modifier.fillMaxSize())
            SignalOverlay(signal, channel, program)
        }
        if (!isGuideOpen) {
            val current = channel
            AnimatedVisibility(showsBanner && current != null, Modifier.align(Alignment.TopEnd).padding(Tokens.Spacing.xl), enter = fadeIn(), exit = fadeOut()) {
                current?.let { ChannelNumberOSD(it) }
            }
            AnimatedVisibility(showsBanner && current != null, Modifier.align(Alignment.BottomCenter).padding(Tokens.Spacing.xl), enter = fadeIn(), exit = fadeOut()) {
                current?.let { ChannelBanner(it, if (showsNext) nextProgram ?: program else program, isShowingNext = showsNext && nextProgram != null) }
            }
        }
    }
}
