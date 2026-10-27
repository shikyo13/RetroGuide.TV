package com.adamhunt.retroguide.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Text
import com.adamhunt.retroguide.ui.theme.LocalTheme
import com.adamhunt.retroguide.ui.theme.Tokens
import com.adamhunt.retroguide.ui.theme.Typography
import kotlin.random.Random

/**
 * Animated analog "snow", shown while a channel is tuning: a few small
 * grayscale frames made once and cycled, scaled up without smoothing.
 */
@Composable
fun StaticNoise(modifier: Modifier = Modifier) {
    val frames = remember { NoiseFrames.frames }
    var index by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) {
        while (true) {
            withFrameMillis { millis -> index = ((millis / NoiseFrames.FRAME_MS) % frames.size).toInt() }
        }
    }
    Canvas(modifier.fillMaxSize()) {
        drawImage(
            frames[index],
            dstSize = IntSize(size.width.toInt(), size.height.toInt()),
            dstOffset = IntOffset.Zero,
            filterQuality = FilterQuality.None,
        )
    }
}

private object NoiseFrames {
    private const val WIDTH = 240
    private const val HEIGHT = 135
    private const val COUNT = 6
    private const val MINIMUM_BRIGHTNESS = 20
    /** 24 frames per second. */
    const val FRAME_MS = 1000L / 24

    val frames: List<ImageBitmap> = List(COUNT) {
        val pixels = IntArray(WIDTH * HEIGHT) {
            val gray = Random.nextInt(MINIMUM_BRIGHTNESS, 256)
            (0xFF shl 24) or (gray shl 16) or (gray shl 8) or gray
        }
        android.graphics.Bitmap.createBitmap(pixels, WIDTH, HEIGHT, android.graphics.Bitmap.Config.ARGB_8888).asImageBitmap()
    }
}

/** Classic color bars with a "No Signal" slate, shown when a stream fails. */
@Composable
fun NoSignalCard(message: String) {
    val theme = LocalTheme.current
    val slate = RoundedCornerShape(Tokens.Radius.large)
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(Modifier.fillMaxSize()) {
            BarRow(Bars.main, Modifier.weight(Bars.MAIN_FRACTION))
            BarRow(Bars.lower, Modifier.weight(1 - Bars.MAIN_FRACTION))
        }
        Column(
            Modifier
                .widthIn(max = Bars.slateWidth)
                .background(Color.Black.copy(alpha = Tokens.Opacity.SCRIM), slate)
                .padding(Tokens.Spacing.xl),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.md),
        ) {
            Text("NO SIGNAL", style = Typography.display.copy(fontFamily = FontFamily.Monospace), color = theme.textPrimary)
            Text(message, style = Typography.body, color = theme.textSecondary, textAlign = TextAlign.Center)
            Text("Retrying automatically…", style = Typography.caption, color = theme.textSecondary)
        }
    }
}

@Composable
private fun BarRow(colors: List<Color>, modifier: Modifier) {
    Row(modifier.fillMaxWidth()) {
        for (color in colors) Box(Modifier.weight(1f).fillMaxHeight().background(color))
    }
}

/** SMPTE-style bars, left to right. */
private object Bars {
    const val MAIN_FRACTION = 0.67f
    val slateWidth = 550.dp
    val main = listOf(0xFFC0C0C0, 0xFFC0C000, 0xFF00C0C0, 0xFF00C000, 0xFFC000C0, 0xFFC00000, 0xFF0000C0).map { Color(it) }
    val lower = listOf(0xFF0000C0, 0xFF131313, 0xFFC000C0, 0xFF131313, 0xFF00C0C0, 0xFF131313, 0xFFC0C0C0).map { Color(it) }
}
