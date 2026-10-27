package com.adamhunt.retroguide.player

import android.view.Display
import android.view.Window
import kotlin.math.abs
import kotlin.math.roundToInt

/** Settings › Playback › Match TV mode on Android. */
enum class MatchTVMode(val title: String, val explanation: String) {
    OFF("Off", "Always use the TV's usual output."),
    FRAME_RATE(
        "Frame rate",
        "Match each program's frame rate for the smoothest motion. The TV blanks briefly more often while you change channels.",
    ),
}

/**
 * Switches the TV's refresh rate to suit what's playing (the Apple app's
 * `DisplayModeController`, frame rate part): the display mode at the current
 * resolution whose refresh rate is a whole multiple of the video's frame rate.
 * HDR follows the player's output, which is standard range on Android for now.
 */
object DisplayModeMatcher {
    /** Refresh rates within this of a whole multiple count as matching (23.976 ≈ 24). */
    private const val TOLERANCE = 0.05

    fun apply(window: Window, frameRate: Double?, mode: MatchTVMode) {
        val display = window.decorView.display ?: return
        val wanted = if (mode == MatchTVMode.FRAME_RATE && frameRate != null) bestMode(display, frameRate) else null
        val id = wanted?.modeId ?: 0
        val attributes = window.attributes
        if (attributes.preferredDisplayModeId == id) return
        attributes.preferredDisplayModeId = id
        window.attributes = attributes
    }

    private fun bestMode(display: Display, frameRate: Double): Display.Mode? {
        val current = display.mode
        return display.supportedModes
            .filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
            .filter { matches(it.refreshRate.toDouble(), frameRate) }
            .minByOrNull { it.refreshRate }
    }

    private fun matches(refreshRate: Double, frameRate: Double): Boolean {
        val multiple = (refreshRate / frameRate).roundToInt()
        return multiple >= 1 && abs(refreshRate - multiple * frameRate) <= TOLERANCE * multiple
    }
}
