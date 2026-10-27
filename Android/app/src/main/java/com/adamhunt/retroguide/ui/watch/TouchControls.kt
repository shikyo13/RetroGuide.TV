package com.adamhunt.retroguide.ui.watch

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Text
import com.adamhunt.retroguide.ui.components.RetroButton
import com.adamhunt.retroguide.ui.theme.LocalTheme
import com.adamhunt.retroguide.ui.theme.Tokens
import com.adamhunt.retroguide.ui.theme.Typography
import kotlin.math.abs

/** What a touch on the picture asks for (the Apple app's `PlayerCommand`). */
enum class PlayerCommand { CHANNEL_UP, CHANNEL_DOWN, SHOW_NOW, SHOW_NEXT, TOGGLE_INFO, OPEN_GUIDE, OPEN_OPTIONS, LAST_CHANNEL }

private object TouchGesture {
    /** A drag shorter than this is a tap, not a swipe. */
    val minimumDistance = 32.dp
    /** Swipes starting this close to the top or bottom edge belong to the system. */
    val systemEdgeMargin = 32.dp
    val iconButtonSize = 44.dp
}

/**
 * Full-screen touch handling while watching on phones and tablets (the Apple
 * app's `PlayerTouchInput`), mirroring the remote: swipe up or down to change
 * channel, right or left for what's on now or next, tap for the banner and
 * on-screen controls.
 */
fun Modifier.playerTouchInput(onCommand: (PlayerCommand) -> Unit): Modifier = this
    .pointerInput(Unit) { detectTapGestures { onCommand(PlayerCommand.TOGGLE_INFO) } }
    .pointerInput(Unit) {
        var start = Offset.Zero
        var total = Offset.Zero
        detectDragGestures(
            onDragStart = { start = it; total = Offset.Zero },
            onDragEnd = {
                val edge = TouchGesture.systemEdgeMargin.toPx()
                if (start.y < edge || start.y > size.height - edge) return@detectDragGestures
                if (total.getDistance() < TouchGesture.minimumDistance.toPx()) return@detectDragGestures
                onCommand(
                    if (abs(total.y) > abs(total.x)) {
                        if (total.y < 0) PlayerCommand.CHANNEL_UP else PlayerCommand.CHANNEL_DOWN
                    } else {
                        if (total.x < 0) PlayerCommand.SHOW_NEXT else PlayerCommand.SHOW_NOW
                    },
                )
            },
        ) { _, amount -> total += amount }
    }

/** On-screen buttons shown with the banner on touch screens (the Apple app's `PlayerTouchControls`). */
@Composable
fun PlayerTouchControls(onCommand: (PlayerCommand) -> Unit, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
        RetroButton("☰ Guide", { onCommand(PlayerCommand.OPEN_GUIDE) }, isPrimary = true)
        RoundButton("⚙", "Options") { onCommand(PlayerCommand.OPEN_OPTIONS) }
        Spacer(Modifier.weight(1f))
        RoundButton("↩", "Last channel") { onCommand(PlayerCommand.LAST_CHANNEL) }
        RoundButton("▼", "Channel down") { onCommand(PlayerCommand.CHANNEL_DOWN) }
        RoundButton("▲", "Channel up") { onCommand(PlayerCommand.CHANNEL_UP) }
    }
}

@Composable
private fun RoundButton(symbol: String, label: String, onClick: () -> Unit) {
    val theme = LocalTheme.current
    Box(
        Modifier
            .size(TouchGesture.iconButtonSize)
            .clip(RoundedCornerShape(percent = 50))
            .background(theme.surfaceRaised.copy(alpha = Tokens.Opacity.SCRIM))
            .clickable(onClickLabel = label, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(symbol, style = Typography.headline, color = theme.textPrimary)
    }
}
