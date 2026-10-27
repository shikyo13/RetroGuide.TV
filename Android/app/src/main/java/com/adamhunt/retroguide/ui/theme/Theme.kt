package com.adamhunt.retroguide.ui.theme

import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

/** Identifiers for the built-in themes (the Apple app's `ThemeID`). */
enum class ThemeId {
    CLASSIC_CABLE, LOCAL_FORECAST, SATURDAY_MORNING, PAY_PER_VIEW, WOOD_PANEL, VHS,
    SYNTHWAVE, MIDNIGHT, CRT_GREEN, AMBER, TELETEXT, MONO;

    /** The free version includes Classic Cable; every other theme is RetroGuide Pro. */
    val isIncludedFree get() = this == CLASSIC_CABLE
}

/** Who a program is for, from its content rating (RetroGuideKit's `Audience`). */
enum class Audience {
    KIDS, FAMILY, TEEN, MATURE, UNRATED;

    companion object {
        fun from(value: String?) = entries.firstOrNull { it.name.equals(value, ignoreCase = true) } ?: UNRATED
    }
}

/** A complete color palette. Every color in the UI comes from the active theme. */
data class Theme(
    val id: ThemeId,
    val name: String,
    /** Top-to-bottom screen background gradient. */
    val background: List<Color>,
    /** Panels, list rows and guide cells. */
    val surface: Color,
    /** Alternate surface for zebra striping and headers. */
    val surfaceRaised: Color,
    /** Fill of the focused guide cell or button. */
    val focusFill: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    /** Text on top of `focusFill`. */
    val textOnFocus: Color,
    /** Brand highlight: logo, channel numbers, progress. */
    val accent: Color,
    /** Secondary highlight: call signs, chips. */
    val accentSecondary: Color,
    /** The vertical "now" line in the guide. */
    val nowLine: Color,
    /** Color of the on-screen channel number overlay. */
    val osd: Color,
    val audienceColors: Map<Audience, Color>,
) {
    val backgroundBrush get() = Brush.verticalGradient(background)

    /** Dark backing for overlays drawn on top of video. */
    val scrim get() = background.last().copy(alpha = Tokens.Opacity.SCRIM)

    fun color(audience: Audience) = audienceColors[audience] ?: textSecondary

    companion object {
        fun of(id: ThemeId) = ThemePalettes.first { it.id == id }
    }
}

val LocalTheme = staticCompositionLocalOf { Theme.of(ThemeId.CLASSIC_CABLE) }
