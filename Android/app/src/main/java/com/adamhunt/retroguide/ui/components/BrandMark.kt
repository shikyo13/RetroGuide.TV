package com.adamhunt.retroguide.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.adamhunt.retroguide.ui.theme.LocalTheme
import com.adamhunt.retroguide.ui.theme.Tokens
import com.adamhunt.retroguide.ui.theme.Typography

/**
 * The RetroGuide.TV brand glyph: a TV with an inset screen and a stand. Same
 * geometry as the Apple app's `TVGlyph` and the app icon.
 */
@Composable
fun TVGlyph(color: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.aspectRatio(Geometry.ASPECT_RATIO)) {
        val unit = size.width
        val body = Rect(0f, 0f, unit, Geometry.BODY_HEIGHT * unit)
        val frame = body.deflate(Geometry.FRAME_THICKNESS * unit)
        val screen = frame.deflate(Geometry.SCREEN_GAP * unit)
        val standHeight = Geometry.STAND_HEIGHT * unit
        val stand = Rect(
            Offset(unit / 2 - Geometry.STAND_WIDTH * unit / 2, body.bottom + Geometry.STAND_GAP * unit),
            Size(Geometry.STAND_WIDTH * unit, standHeight),
        )
        val path = Path().apply {
            fillType = PathFillType.EvenOdd
            addRoundRect(RoundRect(body, CornerRadius(Geometry.BODY_CORNER_RADIUS * unit)))
            addRoundRect(RoundRect(frame, CornerRadius((Geometry.BODY_CORNER_RADIUS - Geometry.FRAME_THICKNESS) * unit)))
            addRoundRect(RoundRect(screen, CornerRadius(Geometry.SCREEN_CORNER_RADIUS * unit)))
            addRoundRect(RoundRect(stand, CornerRadius(standHeight / 2)))
        }
        drawPath(path, color)
    }
}

private object Geometry {
    const val ASPECT_RATIO = 1.18f
    const val BODY_HEIGHT = 0.72f
    const val BODY_CORNER_RADIUS = 0.16f
    const val FRAME_THICKNESS = 0.085f
    const val SCREEN_GAP = 0.05f
    const val SCREEN_CORNER_RADIUS = 0.07f
    const val STAND_WIDTH = 0.44f
    const val STAND_HEIGHT = 0.075f
    const val STAND_GAP = 0.05f
}

/** The wordmark: a small TV glyph, "RetroGuide" and an accented ".TV". */
@Composable
fun BrandMark(style: TextStyle = Typography.headline, modifier: Modifier = Modifier, showsWordmark: Boolean = true) {
    val theme = LocalTheme.current
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        TVGlyph(theme.accent, Modifier.width((style.fontSize.value * GLYPH_TO_TEXT_RATIO).dp))
        if (showsWordmark) Text(
            buildAnnotatedString {
                withStyle(SpanStyle(color = theme.textPrimary)) { append(" RetroGuide") }
                withStyle(SpanStyle(color = theme.accent)) { append(".TV") }
            },
            style = style,
            modifier = Modifier.padding(start = Tokens.Spacing.xs),
        )
    }
}

/** Glyph width as a fraction of the font size (as in the app icon generator). */
private const val GLYPH_TO_TEXT_RATIO = 1.1f
