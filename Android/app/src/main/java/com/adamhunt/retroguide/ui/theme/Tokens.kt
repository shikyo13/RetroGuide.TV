package com.adamhunt.retroguide.ui.theme

import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Layout, shape, motion and type constants (the Apple app's `DesignTokens` and
 * `Typography`). Android TV lays out a 1080p screen on a 960×540 dp canvas,
 * half Apple TV's 1920×1080 points, so these are the tvOS values halved.
 */
object Tokens {
    object Spacing {
        val hairline = 1.dp
        val xxs = 2.dp
        val xs = 4.dp
        val sm = 6.dp
        val md = 10.dp
        val lg = 16.dp
        val xl = 24.dp
        val xxl = 36.dp
    }

    object Radius {
        val small = 4.dp
        val medium = 7.dp
        val large = 12.dp
    }

    object Stroke {
        val thin = 1.dp
        val focus = 2.dp
    }

    object Opacity {
        const val FAINT = 0.08f
        const val SUBTLE = 0.18f
        const val MUTED = 0.45f
        const val STRONG = 0.75f
        const val SCRIM = 0.85f
    }

    object Scale {
        const val FOCUSED = 1.04f
        /** Full-width rows grow less, so they stay inside their column. */
        const val ROW_FOCUSED = 1.02f
    }

    object Motion {
        const val QUICK = 150
        const val STANDARD = 250
        const val RELAXED = 450
    }

    object Control {
        val minimumHeight = 32.dp
    }
}

/** The type scale, sized for viewing from a couch. */
object Typography {
    private val rounded = FontFamily.SansSerif
    private val mono = FontFamily.Monospace

    val display = TextStyle(fontSize = 38.sp, fontWeight = FontWeight.ExtraBold, fontFamily = rounded)
    val title = TextStyle(fontSize = 26.sp, fontWeight = FontWeight.Bold, fontFamily = rounded)
    val headline = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.SemiBold, fontFamily = rounded)
    val body = TextStyle(fontSize = 14.5.sp, fontWeight = FontWeight.Normal)
    val bodyEmphasis = TextStyle(fontSize = 14.5.sp, fontWeight = FontWeight.SemiBold)
    val callout = TextStyle(fontSize = 12.5.sp, fontWeight = FontWeight.Medium)
    val caption = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Medium)
    val captionEmphasis = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Bold)
    val micro = TextStyle(fontSize = 9.5.sp, fontWeight = FontWeight.SemiBold)

    /** Time and channel digits use a monospaced face so columns don't jitter. */
    val clock = TextStyle(fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold, fontFamily = mono)
    val channelNumber = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.ExtraBold, fontFamily = mono)
    val callSign = TextStyle(fontSize = 9.5.sp, fontWeight = FontWeight.ExtraBold, fontFamily = mono)
    val osd = TextStyle(fontSize = 48.sp, fontWeight = FontWeight.Black, fontFamily = mono)
    val linkCode = TextStyle(fontSize = 38.sp, fontWeight = FontWeight.Black, fontFamily = mono)
}
