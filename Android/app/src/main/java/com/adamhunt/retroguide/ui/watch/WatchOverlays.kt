package com.adamhunt.retroguide.ui.watch

import androidx.activity.compose.BackHandler
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import com.adamhunt.retroguide.core.ReminderInfo
import com.adamhunt.retroguide.ui.components.RetroButton
import com.adamhunt.retroguide.ui.LocalFormFactor
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Text
import coil3.compose.AsyncImage
import com.adamhunt.retroguide.core.ChannelInfo
import com.adamhunt.retroguide.core.ProgramInfo
import com.adamhunt.retroguide.player.Signal
import com.adamhunt.retroguide.ui.components.BrandMark
import com.adamhunt.retroguide.ui.components.ChannelBadge
import com.adamhunt.retroguide.ui.components.NoSignalCard
import com.adamhunt.retroguide.ui.components.Panel
import com.adamhunt.retroguide.ui.components.ProgressTrack
import com.adamhunt.retroguide.ui.components.RatingChip
import com.adamhunt.retroguide.ui.components.StaticNoise
import com.adamhunt.retroguide.ui.theme.Audience
import com.adamhunt.retroguide.ui.theme.LocalTheme
import com.adamhunt.retroguide.ui.theme.Tokens
import com.adamhunt.retroguide.ui.theme.Typography
import kotlinx.coroutines.delay

private object BannerLayout {
    /** Narrower than this, the banner drops the logo and the large channel number. */
    val compactWidth = 600.dp
    val logoWidth = 180.dp
    val logoHeight = 55.dp
    val progressHeight = 4.dp
    val progressWidth = 160.dp
    val dividerWidth = 1.dp
    const val SUMMARY_LINES = 2
    const val CLOCK_TICK_MS = 30_000L
}

/** Full-screen states layered over the video: tuning static, intermission and no signal. */
@Composable
fun SignalOverlay(signal: Signal, channel: ChannelInfo?, program: ProgramInfo?) {
    when (signal) {
        Signal.Tuning -> StaticNoise()
        is Signal.NoSignal -> NoSignalCard(signal.message)
        is Signal.Intermission -> if (channel != null && program != null) IntermissionCard(channel)
        Signal.Live, Signal.Off -> Unit
    }
}

/** "We'll be right back", shown in the gap between aligned programs. */
@Composable
private fun IntermissionCard(channel: ChannelInfo) {
    val theme = LocalTheme.current
    Box(Modifier.fillMaxSize().background(theme.backgroundBrush), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.xl)) {
            BrandMark(Typography.display)
            Text("We'll be right back", style = Typography.title, color = theme.textPrimary)
            Text("Up next on ${channel.name}", style = Typography.callout, color = theme.accentSecondary)
        }
    }
}

/** The big glowing channel number in the corner, like an old TV's on-screen display. */
@Composable
fun ChannelNumberOSD(channel: ChannelInfo, modifier: Modifier = Modifier) {
    val theme = LocalTheme.current
    val glow = Shadow(color = theme.osd.copy(alpha = Tokens.Opacity.MUTED), blurRadius = 24f)
    Column(modifier, horizontalAlignment = Alignment.End) {
        Text(channel.number.toString(), style = Typography.osd.copy(shadow = glow), color = theme.osd)
        Text(channel.callSign, style = Typography.headline.copy(shadow = glow, fontFamily = Typography.clock.fontFamily), color = theme.osd)
    }
}

/** Bottom "info bar" showing the channel and what's on now (or next). */
@Composable
fun ChannelBanner(channel: ChannelInfo, program: ProgramInfo?, isShowingNext: Boolean, modifier: Modifier = Modifier) {
    val theme = LocalTheme.current
    var now by remember { mutableDoubleStateOf(nowSeconds()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(BannerLayout.CLOCK_TICK_MS)
            now = nowSeconds()
        }
    }
    val isTouch = LocalFormFactor.current.isTouch
    BoxWithConstraints(modifier.fillMaxWidth()) {
    // A phone held upright has room for the program, not the logo.
    val isCompact = maxWidth < BannerLayout.compactWidth
    Panel(Modifier.fillMaxWidth(), color = theme.scrim) {
        Row(horizontalArrangement = Arrangement.spacedBy(if (isCompact) Tokens.Spacing.sm else Tokens.Spacing.lg), verticalAlignment = Alignment.CenterVertically) {
            ChannelBadge(channel.number, channel.callSign, large = !isCompact)
            Box(Modifier.width(BannerLayout.dividerWidth).height(BannerLayout.logoHeight).background(theme.textSecondary.copy(alpha = Tokens.Opacity.MUTED)))
            if (program == null) {
                Text(channel.name, style = Typography.headline, color = theme.textPrimary, modifier = Modifier.weight(1f))
            } else {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.xxs)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            if (isShowingNext) "UP NEXT" else "NOW", style = Typography.captionEmphasis, color = theme.textOnFocus,
                            modifier = Modifier.background(theme.accent, RoundedCornerShape(Tokens.Radius.small)).padding(horizontal = Tokens.Spacing.xs),
                        )
                        Text(channel.name, style = Typography.caption, color = theme.accentSecondary, maxLines = 1)
                        RatingChip(program.contentRating, Audience.from(program.audience))
                    }
                    Text(program.headline, style = Typography.headline, color = theme.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    program.subheadline?.let { Text(it, style = Typography.callout, color = theme.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis) }
                    program.summary?.takeIf { it.isNotBlank() }?.let {
                        Text(it, style = Typography.caption, color = theme.textSecondary, maxLines = BannerLayout.SUMMARY_LINES, overflow = TextOverflow.Ellipsis)
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.md), verticalAlignment = Alignment.CenterVertically) {
                        Text(ScheduleFormatting.range(program), style = Typography.clock, color = theme.textPrimary)
                        if (!isShowingNext) {
                            ProgressTrack(
                                ScheduleFormatting.progress(program, now),
                                if (isCompact) Modifier.weight(1f) else Modifier.width(BannerLayout.progressWidth),
                                BannerLayout.progressHeight,
                            )
                            Text(ScheduleFormatting.remaining(program, now), style = Typography.caption, color = theme.textSecondary, maxLines = 1, softWrap = false)
                        }
                    }
                    if (!isTouch) RemoteHints()
                }
                if (!isCompact) {
                    program.artwork.logo?.let { logo ->
                        AsyncImage(
                            model = logo, contentDescription = program.headline, contentScale = ContentScale.Fit,
                            modifier = Modifier.size(BannerLayout.logoWidth, BannerLayout.logoHeight),
                        )
                    }
                }
            }
        }
    }
    }
}

/** What the remote's buttons do while watching. */
@Composable
private fun RemoteHints() {
    val theme = LocalTheme.current
    Row(horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.lg)) {
        for (hint in listOf("▲▼ Channel", "◀ ▶ Now / Next", "● Guide", "⏯ Last channel")) {
            Text(hint, style = Typography.caption, color = theme.textSecondary)
        }
    }
}

/** After the sleep timer stops playback: Select starts the channel again. */
@Composable
fun SleepFinishedCard(modifier: Modifier = Modifier) {
    val theme = LocalTheme.current
    Panel(modifier, color = theme.surface) {
        Text("Sleep timer finished", style = Typography.title, color = theme.textPrimary)
        Text(if (LocalFormFactor.current.isTouch) "Tap to resume watching." else "Press Select to resume watching.", style = Typography.body, color = theme.textSecondary)
    }
}

/** Parental controls leave nothing to show (the Apple app's `ParentalEmptyView`). Select opens the guide's Settings. */
@Composable
fun NoAllowedChannelsCard(modifier: Modifier = Modifier) {
    val theme = LocalTheme.current
    Panel(modifier, color = theme.surface) {
        Text("No allowed channels", style = Typography.title, color = theme.textPrimary)
        Text("No available channels match your parental controls. A parent can change the lineup or content restrictions in Settings › Parental Controls (press Select, then open Settings).",
            style = Typography.body, color = theme.textSecondary)
    }
}

/** A reminded program has started (the Apple app's "Program reminder" alert). */
@Composable
fun ReminderDueCard(reminder: ReminderInfo, modifier: Modifier = Modifier, onWatch: () -> Unit, onDismiss: () -> Unit) {
    val theme = LocalTheme.current
    val watch = remember { FocusRequester() }
    BackHandler(onBack = onDismiss)
    Panel(modifier.width(WatchOverlayLayout.alertWidth), color = theme.surface) {
        Text("Program reminder", style = Typography.title, color = theme.textPrimary)
        Text("${reminder.title} is starting on ${reminder.channelName}.", style = Typography.body, color = theme.textSecondary)
        Row(horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.md)) {
            RetroButton("Watch now", onWatch, Modifier.focusRequester(watch), isPrimary = true)
            RetroButton("Dismiss", onDismiss)
        }
    }
    LaunchedEffect(reminder.id) { runCatching { watch.requestFocus() } }
}

/** A short message with an OK button (the Apple app's simple alerts). */
@Composable
fun MessageCard(title: String, message: String, modifier: Modifier = Modifier, onDismiss: () -> Unit) {
    val theme = LocalTheme.current
    val ok = remember { FocusRequester() }
    BackHandler(onBack = onDismiss)
    Panel(modifier.width(WatchOverlayLayout.alertWidth), color = theme.surface) {
        Text(title, style = Typography.title, color = theme.textPrimary)
        Text(message, style = Typography.body, color = theme.textSecondary)
        RetroButton("OK", onDismiss, Modifier.focusRequester(ok), isPrimary = true)
    }
    LaunchedEffect(message) { runCatching { ok.requestFocus() } }
}

private object WatchOverlayLayout {
    val alertWidth = 420.dp
}
