package com.adamhunt.retroguide.ui.guide

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Text
import coil3.compose.AsyncImage
import com.adamhunt.retroguide.core.ChannelInfo
import com.adamhunt.retroguide.core.ProgramInfo
import com.adamhunt.retroguide.ui.components.BrandMark
import com.adamhunt.retroguide.ui.components.LocalShowsScanlines
import com.adamhunt.retroguide.ui.components.PictureWindow
import com.adamhunt.retroguide.ui.components.RatingChip
import com.adamhunt.retroguide.ui.components.RetroButton
import com.adamhunt.retroguide.ui.components.crtEffect
import com.adamhunt.retroguide.ui.components.screenBackground
import com.adamhunt.retroguide.ui.theme.Audience
import com.adamhunt.retroguide.ui.theme.LocalTheme
import com.adamhunt.retroguide.ui.theme.Tokens
import com.adamhunt.retroguide.ui.theme.Typography
import com.adamhunt.retroguide.ui.watch.ScheduleFormatting
import com.adamhunt.retroguide.ui.watch.nowSeconds
import kotlinx.coroutines.delay
import kotlin.math.abs

/** Sizes of the touch guide (the Apple app's iPhone and iPad guide). */
private object TouchGuideLayout {
    val margin = 12.dp
    /** The live picture's width: a share of the screen, smaller in landscape. */
    const val PORTRAIT_PICTURE_FRACTION = 0.45f
    const val LANDSCAPE_PICTURE_FRACTION = 0.3f
    /** Narrower than this shows two half-hour slots instead of three. */
    val compactWidth = 600.dp
    /** A sideways drag this long pages the grid through time. */
    val swipeDistance = 48.dp
    val headerButtonSize = 40.dp
}

/** What the touch guide's buttons do. */
class TouchGuideActions(
    val onTune: (ChannelInfo) -> Unit,
    val onToggleFavorites: () -> Unit,
    val onReminder: () -> Unit,
    val onSearch: () -> Unit,
    val onSettings: () -> Unit,
    val onOptions: () -> Unit,
    val onClose: () -> Unit,
)

/**
 * The program guide on phones and tablets (the Apple app's `GuideTouchView`):
 * tap to preview, tap again or press Watch to tune, scroll through channels
 * and page through time with the arrows or a sideways swipe. The live picture
 * is drawn into [onPictureWindow]'s place by the watch screen.
 */
@Composable
fun TouchGuideScreen(
    model: GuideModel,
    tunedChannel: ChannelInfo?,
    favoritesOnly: Boolean,
    isReminderSet: (ProgramInfo) -> Boolean,
    actions: TouchGuideActions,
    onPictureWindow: (PictureWindow) -> Unit,
) {
    val theme = LocalTheme.current
    val density = LocalDensity.current
    val windowStart by model.windowStart.collectAsState()
    val schedules by model.schedules.collectAsState()
    val focus by model.focus.collectAsState()
    val slots by model.visibleSlots.collectAsState()
    var now by remember { mutableDoubleStateOf(nowSeconds()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(GuideLayout.CLOCK_TICK_MS)
            now = nowSeconds()
            model.followClock()
        }
    }
    val focusedRow = (focus as? GuideModel.Focus.Program)?.row
    val selected = remember(focus, schedules) { model.selectedProgram }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val isPortrait = maxHeight > maxWidth
        val channelColumnWidth = if (maxWidth < TouchGuideLayout.compactWidth) GuideLayout.compactChannelColumnWidth else GuideLayout.channelColumnWidth
        LaunchedEffect(maxWidth) {
            model.setVisibleSlots(if (maxWidth < TouchGuideLayout.compactWidth) GuideModel.Time.COMPACT_VISIBLE_SLOTS else GuideModel.Time.VISIBLE_SLOTS)
        }
        val pictureWidth = maxWidth * if (isPortrait) TouchGuideLayout.PORTRAIT_PICTURE_FRACTION else TouchGuideLayout.LANDSCAPE_PICTURE_FRACTION
        val pictureHeight = pictureWidth * 9 / 16
        var picture by remember { mutableStateOf<PictureWindow?>(null) }
        Column(
            Modifier
                .fillMaxSize()
                .screenBackground(theme, picture)
                .crtEffect(LocalShowsScanlines.current, picture)
                .safeDrawingPadding()
                .padding(horizontal = TouchGuideLayout.margin),
            verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.sm),
        ) {
            Header(now, favoritesOnly, selected?.takeIf { it.start > now }?.let(isReminderSet), actions)
            Row(Modifier.height(pictureHeight), horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.sm)) {
                Box(
                    Modifier
                        .size(pictureWidth, pictureHeight)
                        .border(GuideLayout.cellSpacing, theme.surfaceRaised, RoundedCornerShape(Tokens.Radius.medium))
                        .onGloballyPositioned { coordinates ->
                            val bounds = coordinates.boundsInRoot()
                            val window = with(density) {
                                PictureWindow(DpOffset(bounds.left.toDp(), bounds.top.toDp()), DpSize(bounds.width.toDp(), bounds.height.toDp()))
                            }
                            picture = window
                            onPictureWindow(window)
                        },
                )
                Details(selected, model.selectedChannel, now, Modifier.weight(1f)) { model.selectedChannel?.let(actions.onTune) }
            }
            GuideRuler(windowStart, now, slots, channelColumnWidth) { TimeControls(model, now, windowStart) }
            GuideGrid(
                model, schedules, windowStart, slots, focusedRow, selected, now, isTouch = true,
                modifier = Modifier.weight(1f).pointerInput(Unit) {
                    var dragged = 0f
                    detectHorizontalDragGestures(
                        onDragStart = { dragged = 0f },
                        onDragEnd = {
                            if (abs(dragged) >= TouchGuideLayout.swipeDistance.toPx()) model.shiftWindow(if (dragged < 0) 1 else -1)
                        },
                    ) { _, amount -> dragged += amount }
                },
                channelColumnWidth = channelColumnWidth,
                onTune = actions.onTune,
            )
        }
    }
}

@Composable
private fun Header(now: Double, favoritesOnly: Boolean, isReminderSet: Boolean?, actions: TouchGuideActions) {
    val theme = LocalTheme.current
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.xs)) {
        BrandMark(Typography.headline)
        Spacer(Modifier.weight(1f))
        Text(ScheduleFormatting.time(now), style = Typography.clock, color = theme.accent)
        IconButton(if (favoritesOnly) "★" else "☆", "Favorites", actions.onToggleFavorites)
        isReminderSet?.let { IconButton(if (it) "🔕" else "🔔", if (it) "Cancel reminder" else "Remind me", actions.onReminder) }
        IconButton("⌕", "Search", actions.onSearch)
        IconButton("⚙", "Settings", actions.onSettings)
        IconButton("✕", "Close guide", actions.onClose)
    }
}

/** A round header button showing a symbol. */
@Composable
private fun IconButton(symbol: String, label: String, onClick: () -> Unit) {
    val theme = LocalTheme.current
    Box(
        Modifier
            .size(TouchGuideLayout.headerButtonSize)
            .clip(RoundedCornerShape(percent = 50))
            .background(theme.surfaceRaised)
            .clickable(onClickLabel = label, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(symbol, style = Typography.headline, color = theme.textPrimary)
    }
}

/** Earlier, now and later above the channel column (the Apple app's `GuideTimeControls`). */
@Composable
private fun TimeControls(model: GuideModel, now: Double, windowStart: Double) {
    val theme = LocalTheme.current
    val isShowingNow = windowStart <= GuideModel.slotStart(now)
    @Composable
    fun control(symbol: String, isEnabled: Boolean, action: () -> Unit) {
        Box(
            Modifier.fillMaxHeight().padding(horizontal = Tokens.Spacing.sm).clickable(enabled = isEnabled, onClick = action),
            contentAlignment = Alignment.Center,
        ) {
            Text(symbol, style = Typography.bodyEmphasis, color = if (isEnabled) theme.accent else theme.textSecondary.copy(alpha = Tokens.Opacity.MUTED))
        }
    }
    control("◀", !isShowingNow) { model.shiftWindow(-1) }
    control("Now", !isShowingNow, model::jumpToNow)
    control("▶", true) { model.shiftWindow(1) }
}

/** The selected program and a Watch button (the Apple app's `GuidePreviewPanel`). */
@Composable
private fun Details(program: ProgramInfo?, channel: ChannelInfo?, now: Double, modifier: Modifier, onWatch: () -> Unit) {
    val theme = LocalTheme.current
    Box(modifier.fillMaxHeight().clip(RoundedCornerShape(Tokens.Radius.medium)).background(theme.surface)) {
        program?.artwork?.backdrop?.let {
            AsyncImage(model = it, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
            Box(Modifier.fillMaxSize().background(theme.surface.copy(alpha = Tokens.Opacity.STRONG)))
        }
        if (program != null && channel != null) {
            Column(Modifier.padding(Tokens.Spacing.sm), verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.xxs)) {
                Row(horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
                    Text("${channel.number} · ${channel.name}", style = Typography.caption, color = theme.accentSecondary, maxLines = 1)
                    RatingChip(program.contentRating, Audience.from(program.audience))
                }
                Text(program.headline, style = Typography.bodyEmphasis, color = theme.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                program.subheadline?.let { Text(it, style = Typography.caption, color = theme.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis) }
                Text(
                    if (program.start <= now) "${ScheduleFormatting.range(program)} · ${ScheduleFormatting.remaining(program, now)}" else ScheduleFormatting.range(program),
                    style = Typography.clock, color = theme.accent, maxLines = 1,
                )
                Spacer(Modifier.weight(1f, fill = false))
                RetroButton("▶ Watch", onWatch, isPrimary = true)
            }
        }
    }
}
