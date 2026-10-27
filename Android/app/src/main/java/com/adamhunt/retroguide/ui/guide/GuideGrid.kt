package com.adamhunt.retroguide.ui.guide

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Text
import com.adamhunt.retroguide.core.ChannelInfo
import com.adamhunt.retroguide.core.ProgramInfo
import com.adamhunt.retroguide.ui.theme.Audience
import com.adamhunt.retroguide.ui.theme.LocalTheme
import com.adamhunt.retroguide.ui.theme.Tokens
import com.adamhunt.retroguide.ui.theme.Typography
import com.adamhunt.retroguide.ui.watch.ScheduleFormatting
import kotlin.math.max
import kotlin.math.min

/** The grid's channel badge column. */
private object ChannelColumn {
    val badgeWidth = 36.dp
}

/**
 * The time ruler over the grid: the date (or [leading], the touch guide's
 * time controls) above the channel column, then a time per slot.
 */
@Composable
internal fun GuideRuler(
    windowStart: Double,
    now: Double,
    slots: Int,
    channelColumnWidth: Dp = GuideLayout.channelColumnWidth,
    leading: (@Composable RowScope.() -> Unit)? = null,
) {
    val theme = LocalTheme.current
    Row(Modifier.fillMaxWidth().height(GuideLayout.rulerHeight), verticalAlignment = Alignment.CenterVertically) {
        if (leading != null) {
            Row(Modifier.width(channelColumnWidth), verticalAlignment = Alignment.CenterVertically, content = leading)
        } else {
            Text(
                java.text.DateFormat.getDateInstance(java.text.DateFormat.MEDIUM).format(java.util.Date((max(now, windowStart) * 1000).toLong())).uppercase(),
                style = Typography.caption, color = theme.textSecondary, modifier = Modifier.width(channelColumnWidth),
            )
        }
        for (slot in 0 until slots) {
            Text(
                ScheduleFormatting.time(windowStart + slot * GuideModel.Time.SLOT), style = Typography.clock, color = theme.textPrimary,
                modifier = Modifier.weight(1f).padding(start = Tokens.Spacing.xs),
            )
        }
    }
}

/**
 * Channels down the side and their programs across the time window. On TV
 * the remote moves focus (the list follows it); on touch screens the list
 * scrolls, a tap selects a program and a second tap on it watches the channel.
 */
@Composable
internal fun GuideGrid(
    model: GuideModel,
    schedules: Map<String, List<ProgramInfo>>,
    windowStart: Double,
    slots: Int,
    focusedRow: Int?,
    focusedProgram: ProgramInfo?,
    now: Double,
    isTouch: Boolean,
    modifier: Modifier = Modifier,
    channelColumnWidth: Dp = GuideLayout.channelColumnWidth,
    onTune: (ChannelInfo) -> Unit = {},
) {
    val theme = LocalTheme.current
    val listState = rememberLazyListState(initialFirstVisibleItemIndex = if (isTouch) max(0, (focusedRow ?: 0) - 1) else 0)
    if (!isTouch) {
        LaunchedEffect(focusedRow) {
            val row = focusedRow ?: return@LaunchedEffect
            val first = listState.firstVisibleItemIndex
            if (row < first) listState.animateScrollToItem(row)
            else if (row >= first + GuideLayout.VISIBLE_ROWS) listState.animateScrollToItem(row - GuideLayout.VISIBLE_ROWS + 1)
        }
    }
    val window = GuideModel.Time.SLOT * slots
    val windowEnd = windowStart + window
    val height = if (isTouch) Modifier.fillMaxSize() else
        Modifier.fillMaxWidth().height(GuideLayout.rowHeight * GuideLayout.VISIBLE_ROWS + GuideLayout.rowSpacing * (GuideLayout.VISIBLE_ROWS - 1))
    BoxWithConstraints(modifier.then(height)) {
        val gridWidth = maxWidth - channelColumnWidth
        val rowHeight = if (isTouch) GuideLayout.touchRowHeight else GuideLayout.rowHeight
        LazyColumn(state = listState, verticalArrangement = Arrangement.spacedBy(GuideLayout.rowSpacing), userScrollEnabled = isTouch) {
            itemsIndexed(model.channels, key = { _, channel -> channel.id }) { index, channel ->
                Row(Modifier.height(rowHeight)) {
                    ChannelCell(channel, channelColumnWidth, isFocusedRow = index == focusedRow, onClick = if (isTouch) ({ onTune(channel) }) else null)
                    Box(Modifier.width(gridWidth).fillMaxHeight()) {
                        for (program in schedules[channel.id].orEmpty()) {
                            if (program.end <= windowStart || program.start >= windowEnd) continue
                            val x = gridWidth * ((max(program.start, windowStart) - windowStart) / window).toFloat()
                            val width = gridWidth * ((min(program.end, windowEnd) - max(program.start, windowStart)) / window).toFloat()
                            val isFocused = index == focusedRow && program.id == focusedProgram?.id
                            ProgramCell(
                                program, x, width - GuideLayout.cellSpacing, isFocused,
                                continuesBefore = program.start < windowStart, continuesAfter = program.end > windowEnd,
                                onClick = if (isTouch) ({ if (isFocused) onTune(channel) else model.select(index, program) }) else null,
                            )
                        }
                    }
                }
            }
        }
        if (now in windowStart..windowEnd) {
            val x = channelColumnWidth + gridWidth * ((now - windowStart) / window).toFloat()
            Box(Modifier.offset(x = x).width(GuideLayout.nowLineWidth).fillMaxHeight().background(theme.nowLine))
        }
    }
}

@Composable
private fun ChannelCell(channel: ChannelInfo, columnWidth: Dp, isFocusedRow: Boolean, onClick: (() -> Unit)?) {
    val theme = LocalTheme.current
    Row(
        Modifier
            .width(columnWidth - GuideLayout.cellSpacing)
            .fillMaxHeight()
            .clip(RoundedCornerShape(Tokens.Radius.small))
            .background(theme.surface)
            .then(if (isFocusedRow) Modifier.border(Tokens.Stroke.thin, theme.focusFill, RoundedCornerShape(Tokens.Radius.small)) else Modifier)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = Tokens.Spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.sm),
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(ChannelColumn.badgeWidth)) {
            Text(channel.number.toString(), style = Typography.channelNumber, color = theme.accent)
            Text(channel.callSign, style = Typography.callSign, color = theme.accentSecondary, maxLines = 1)
        }
        Text(
            channel.name, style = if (columnWidth < GuideLayout.channelColumnWidth) Typography.caption else Typography.callout,
            color = theme.textPrimary, maxLines = 2, overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun ProgramCell(
    program: ProgramInfo,
    x: Dp,
    width: Dp,
    isFocused: Boolean,
    continuesBefore: Boolean,
    continuesAfter: Boolean,
    onClick: (() -> Unit)?,
) {
    val theme = LocalTheme.current
    if (width <= 0.dp) return
    Row(
        Modifier
            .offset(x = x)
            .width(width)
            .fillMaxHeight()
            .clip(RoundedCornerShape(Tokens.Radius.small))
            .background(if (isFocused) theme.focusFill else theme.surface)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.width(GuideLayout.audienceStripeWidth).fillMaxHeight().background(theme.color(Audience.from(program.audience))))
        if (continuesBefore) Text("◀", style = Typography.micro, color = if (isFocused) theme.textOnFocus else theme.textSecondary, modifier = Modifier.padding(start = Tokens.Spacing.xs))
        if (width >= GuideLayout.minimumTitleWidth) {
            Column(Modifier.weight(1f).padding(horizontal = Tokens.Spacing.sm)) {
                Text(program.headline, style = Typography.bodyEmphasis, color = if (isFocused) theme.textOnFocus else theme.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (width >= GuideLayout.minimumSubtitleWidth) {
                    program.subheadline?.let {
                        Text(it, style = Typography.caption, color = if (isFocused) theme.textOnFocus else theme.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        } else {
            Spacer(Modifier.weight(1f))
        }
        if (continuesAfter) Text("▶", style = Typography.micro, color = if (isFocused) theme.textOnFocus else theme.textSecondary, modifier = Modifier.padding(end = Tokens.Spacing.xs))
    }
}
