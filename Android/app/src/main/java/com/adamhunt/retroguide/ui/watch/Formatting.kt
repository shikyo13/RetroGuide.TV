package com.adamhunt.retroguide.ui.watch

import com.adamhunt.retroguide.core.ProgramInfo
import java.text.DateFormat
import java.util.Date
import kotlin.math.max
import kotlin.math.roundToLong

/** Times and durations as the guide shows them (the Apple app's `ScheduleFormatting`). */
object ScheduleFormatting {
    private const val SECONDS_PER_MINUTE = 60
    private const val MINUTES_PER_HOUR = 60

    fun time(seconds: Double): String = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date((seconds * 1000).toLong()))

    /** "1:22 PM – 3:15 PM". */
    fun range(program: ProgramInfo) = "${time(program.start)} – ${time(program.end)}"

    /** "6m left" or "1h 12m left". */
    fun remaining(program: ProgramInfo, now: Double): String {
        val minutes = max(0L, ((program.end - now) / SECONDS_PER_MINUTE).roundToLong())
        val hours = minutes / MINUTES_PER_HOUR
        return if (hours > 0) "${hours}h ${minutes % MINUTES_PER_HOUR}m left" else "${minutes}m left"
    }

    fun progress(program: ProgramInfo, now: Double): Float =
        if (program.end <= program.start) 0f else ((now - program.start) / (program.end - program.start)).toFloat()
}

/** Seconds since 1970, as the core uses. */
fun nowSeconds() = System.currentTimeMillis() / 1000.0
