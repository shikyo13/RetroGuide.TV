package com.adamhunt.retroguide.ui.guide

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.ClipOp
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Text
import coil3.compose.AsyncImage
import com.adamhunt.retroguide.core.ChannelInfo
import com.adamhunt.retroguide.core.ProgramInfo
import com.adamhunt.retroguide.ui.components.BrandMark
import com.adamhunt.retroguide.ui.components.PictureWindow
import com.adamhunt.retroguide.ui.components.screenBackground
import com.adamhunt.retroguide.ui.components.LocalShowsScanlines
import com.adamhunt.retroguide.ui.components.crtEffect
import com.adamhunt.retroguide.ui.components.RatingChip
import com.adamhunt.retroguide.ui.theme.Audience
import com.adamhunt.retroguide.ui.theme.LocalTheme
import com.adamhunt.retroguide.ui.theme.Tokens
import com.adamhunt.retroguide.ui.theme.Typography
import com.adamhunt.retroguide.ui.watch.ScheduleFormatting
import com.adamhunt.retroguide.ui.watch.nowSeconds
import kotlinx.coroutines.delay
import kotlin.math.max
import kotlin.math.min

/** Sizes of the guide (the Apple app's `GuideLayout`, halved for Android TV's dp grid). */
object GuideLayout {
    val margin = 40.dp
    val top = 20.dp
    val headerHeight = 40.dp
    val sectionSpacing = 8.dp
    val previewHeight = 170.dp
    val previewWidth = previewHeight * 16 / 9
    val channelColumnWidth = 150.dp
    /** A phone held upright: the channel's number and call sign, with a short name. */
    val compactChannelColumnWidth = 104.dp
    val rowHeight = 39.dp
    /** Touch rows are tall enough to tap. */
    val touchRowHeight = 48.dp
    val rowSpacing = 3.dp
    val cellSpacing = 2.dp
    val rulerHeight = 22.dp
    val audienceStripeWidth = 2.5.dp
    val nowLineWidth = 1.5.dp
    val minimumTitleWidth = 35.dp
    val minimumSubtitleWidth = 110.dp
    const val VISIBLE_ROWS = 6
    const val CLOCK_TICK_MS = 30_000L

    /** Where the live picture sits while the guide is open. */
    val previewTop get() = top + headerHeight + sectionSpacing
    val previewWindow get() = PictureWindow(DpOffset(margin, previewTop), DpSize(previewWidth, previewHeight))
}

/**
 * The top row's buttons, left to right. Options sits on the live picture
 * (the Apple app's `GuideLiveControls`), reached with Left from Favorites.
 */
enum class GuideHeaderButton { OPTIONS, FAVORITES, REMINDER, SEARCH, SETTINGS }

@Composable
fun GuideScreen(model: GuideModel, tunedChannel: ChannelInfo?, favoritesOnly: Boolean, isReminderSet: (ProgramInfo) -> Boolean) {
    val theme = LocalTheme.current
    val windowStart by model.windowStart.collectAsState()
    val schedules by model.schedules.collectAsState()
    val focus by model.focus.collectAsState()
    var now by remember { mutableDoubleStateOf(nowSeconds()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(GuideLayout.CLOCK_TICK_MS)
            now = nowSeconds()
            model.followClock()
        }
    }
    val focusedRow = (focus as? GuideModel.Focus.Program)?.row
    // In the top row, the details stay on the program focus came up from.
    val selectedProgram = remember(focus, schedules) { model.selectedProgram }
    val focusedProgram = (focus as? GuideModel.Focus.Program)?.let { selectedProgram }
    Column(
        Modifier
            .fillMaxSize()
            .screenBackground(theme, GuideLayout.previewWindow)
            .crtEffect(LocalShowsScanlines.current, GuideLayout.previewWindow)
            .padding(start = GuideLayout.margin, end = GuideLayout.margin, top = GuideLayout.top),
        verticalArrangement = Arrangement.spacedBy(GuideLayout.sectionSpacing),
    ) {
        val buttons = remember(focus, schedules, now) { model.headerButtons(now) }
        val focusedButton = (focus as? GuideModel.Focus.Header)?.let { buttons.getOrNull(it.index) }
        val reminderTitle = selectedProgram?.takeIf { GuideHeaderButton.REMINDER in buttons }
            ?.let { if (isReminderSet(it)) "🔔 Cancel reminder" else "🔔 Remind me" }
        Header(now, focusedButton, favoritesOnly, reminderTitle)
        Row(Modifier.height(GuideLayout.previewHeight), horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.lg)) {
            // The live picture is drawn here by the video surface underneath.
            Box(
                Modifier
                    .size(GuideLayout.previewWidth, GuideLayout.previewHeight)
                    .border(GuideLayout.cellSpacing, theme.surfaceRaised, RoundedCornerShape(Tokens.Radius.medium)),
            )
            ProgramDetails(selectedProgram, model.selectedChannel, now, Modifier.weight(1f))
        }
        val slots by model.visibleSlots.collectAsState()
        GuideRuler(windowStart, now, slots)
        GuideGrid(model, schedules, windowStart, slots, focusedRow, focusedProgram, now, isTouch = false)
    }
}

/**
 * The channel tag and Options button on the live picture. The video surface
 * covers whatever the guide draws there, so the watch screen draws these over it.
 */
@Composable
fun GuidePreviewChrome(model: GuideModel, tunedChannel: ChannelInfo?) {
    val theme = LocalTheme.current
    val focus by model.focus.collectAsState()
    val isOptionsFocused = (focus as? GuideModel.Focus.Header)?.index == 0
    Box(Modifier.fillMaxSize().padding(Tokens.Spacing.sm)) {
        tunedChannel?.let {
            Text(
                "${it.number} ${it.callSign}", style = Typography.callSign, color = theme.osd,
                modifier = Modifier.background(Color.Black.copy(alpha = Tokens.Opacity.MUTED)).padding(horizontal = Tokens.Spacing.xs),
            )
        }
        HeaderButton("⚙ Options", isOptionsFocused, Modifier.align(Alignment.BottomStart))
    }
}

@Composable
private fun Header(now: Double, focusedButton: GuideHeaderButton?, favoritesOnly: Boolean, reminderTitle: String?) {
    val theme = LocalTheme.current
    Row(
        Modifier.fillMaxWidth().height(GuideLayout.headerHeight),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.lg),
    ) {
        BrandMark(Typography.headline)
        Spacer(Modifier.weight(1f))
        Text(ScheduleFormatting.time(now), style = Typography.clock, color = theme.accent)
        Text(if (focusedButton != null) "◀ Back: close guide" else "◀ Back: menus", style = Typography.caption, color = theme.textSecondary)
        HeaderButton(if (favoritesOnly) "★ All channels" else "☆ Favorites", focusedButton == GuideHeaderButton.FAVORITES)
        reminderTitle?.let { HeaderButton(it, focusedButton == GuideHeaderButton.REMINDER) }
        HeaderButton("⌕ Search", focusedButton == GuideHeaderButton.SEARCH)
        HeaderButton("⚙ Settings", focusedButton == GuideHeaderButton.SETTINGS)
    }
}

/** A top-row button; the guide moves focus itself (see ``GuideModel``). */
@Composable
private fun HeaderButton(title: String, isFocused: Boolean, modifier: Modifier = Modifier) {
    val theme = LocalTheme.current
    Text(
        title,
        style = Typography.bodyEmphasis,
        color = if (isFocused) theme.textOnFocus else theme.textPrimary,
        maxLines = 1,
        modifier = modifier
            .clip(RoundedCornerShape(percent = 50))
            .background(if (isFocused) theme.focusFill else theme.surfaceRaised)
            .padding(horizontal = Tokens.Spacing.lg, vertical = Tokens.Spacing.xs),
    )
}

@Composable
private fun ProgramDetails(program: ProgramInfo?, channel: ChannelInfo?, now: Double, modifier: Modifier) {
    val theme = LocalTheme.current
    Box(modifier.fillMaxHeight().clip(RoundedCornerShape(Tokens.Radius.medium)).background(theme.surface)) {
        program?.artwork?.backdrop?.let {
            AsyncImage(model = it, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
            Box(Modifier.fillMaxSize().background(Brush.horizontalGradient(listOf(theme.surface, theme.surface.copy(alpha = Tokens.Opacity.STRONG), Color.Transparent))))
        }
        if (program != null && channel != null) {
            Column(Modifier.padding(Tokens.Spacing.md), verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.xxs)) {
                Row(horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
                    Text("${channel.number} · ${channel.name}", style = Typography.callout, color = theme.accentSecondary)
                    RatingChip(program.contentRating, Audience.from(program.audience))
                }
                val logo = program.artwork.logo
                if (logo != null) {
                    AsyncImage(model = logo, contentDescription = program.headline, contentScale = ContentScale.Fit,
                        alignment = Alignment.CenterStart, modifier = Modifier.height(48.dp).width(220.dp))
                } else {
                    Text(program.headline, style = Typography.title, color = theme.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                program.subheadline?.let { Text(it, style = Typography.bodyEmphasis, color = theme.textPrimary, maxLines = 1) }
                val timing = if (program.start <= now) "${ScheduleFormatting.range(program)} · ${ScheduleFormatting.remaining(program, now)}" else ScheduleFormatting.range(program)
                Text(timing, style = Typography.clock, color = theme.accent)
                program.summary?.let { Text(it, style = Typography.caption, color = theme.textSecondary, maxLines = 3, overflow = TextOverflow.Ellipsis) }
            }
        }
    }
}
