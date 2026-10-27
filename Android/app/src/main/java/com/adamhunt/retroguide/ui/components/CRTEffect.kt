package com.adamhunt.retroguide.ui.components

import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.ClipOp
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.unit.dp
import kotlin.math.hypot

/** Whether menus draw CRT scanlines (Settings › Picture › Scanlines on menus). */
val LocalShowsScanlines = compositionLocalOf { true }

/** The Apple app's `ScanlineOverlay` spec, halved for Android TV's dp grid. */
private object Scanlines {
    val spacing = 2.dp
    val thickness = 0.75.dp
    const val LINE_OPACITY = 0.16f
    const val VIGNETTE_OPACITY = 0.55f
    /** Vignette radii as fractions of the distance from the center to a corner. */
    const val VIGNETTE_START = 0.45f
    const val VIGNETTE_END = 1.2f
}

/**
 * Subtle CRT scanlines (and a vignette) over a menu screen, never over the
 * live picture: [window] is left clean. Draws nothing when [enabled] is off.
 */
fun Modifier.crtEffect(enabled: Boolean, window: PictureWindow? = null): Modifier = drawWithContent {
    drawContent()
    if (!enabled) return@drawWithContent
    val hole = Path().apply {
        window?.let {
            addRoundRect(
                RoundRect(
                    Rect(Offset(it.offset.x.toPx(), it.offset.y.toPx()), Size(it.size.width.toPx(), it.size.height.toPx())),
                    CornerRadius(it.cornerRadius.toPx()),
                ),
            )
        }
    }
    clipPath(hole, ClipOp.Difference) {
        val line = Color.Black.copy(alpha = Scanlines.LINE_OPACITY)
        val step = Scanlines.spacing.toPx()
        val thickness = Scanlines.thickness.toPx()
        var y = 0f
        while (y < size.height) {
            drawRect(line, Offset(0f, y), Size(size.width, thickness))
            y += step
        }
        val halfDiagonal = hypot(size.width, size.height) / 2
        drawRect(
            Brush.radialGradient(
                Scanlines.VIGNETTE_START / Scanlines.VIGNETTE_END to Color.Transparent,
                1f to Color.Black.copy(alpha = Scanlines.VIGNETTE_OPACITY),
                center = center,
                radius = halfDiagonal * Scanlines.VIGNETTE_END,
            ),
        )
    }
}
