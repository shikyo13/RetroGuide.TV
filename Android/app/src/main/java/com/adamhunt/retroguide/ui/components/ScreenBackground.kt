package com.adamhunt.retroguide.ui.components

import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.ClipOp
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import com.adamhunt.retroguide.ui.theme.Theme
import com.adamhunt.retroguide.ui.theme.Tokens

/** Where the live picture shows through a screen, from the screen's top-left corner. */
data class PictureWindow(val offset: DpOffset, val size: DpSize, val cornerRadius: Dp = Tokens.Radius.medium)

/**
 * The theme's background, leaving [window] open: the video surface is drawn
 * behind the app's window, so a screen shows the picture by not painting over it.
 * Apply it to a layout that fills the screen.
 */
fun Modifier.screenBackground(theme: Theme, window: PictureWindow?): Modifier = drawBehind {
    if (window == null) {
        drawRect(theme.backgroundBrush)
        return@drawBehind
    }
    val hole = Path().apply {
        addRoundRect(
            RoundRect(
                Rect(Offset(window.offset.x.toPx(), window.offset.y.toPx()), Size(window.size.width.toPx(), window.size.height.toPx())),
                CornerRadius(window.cornerRadius.toPx()),
            ),
        )
    }
    clipPath(hole, ClipOp.Difference) { drawRect(theme.backgroundBrush) }
}

/** Live TV in the bottom-right corner while Search or Settings covers the screen. */
object CornerPicture {
    private val margin = 40.dp
    private val size = DpSize(240.dp, 135.dp)

    fun window(screen: DpSize) = PictureWindow(
        DpOffset(screen.width - margin - size.width, screen.height - margin - size.height),
        size,
    )
}
