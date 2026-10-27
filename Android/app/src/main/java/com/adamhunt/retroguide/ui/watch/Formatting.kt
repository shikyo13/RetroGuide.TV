package com.adamhunt.retroguide.ui.watch

import com.adamhunt.retroguide.core.ProgramInfo
import java.text.DateFormat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.Date
import java.util.Locale
import kotlin.math.max
import kotlin.math.roundToLong

/** Times and durations as the guide shows them (the Apple app's `ScheduleFormatting`). */
object ScheduleFormatting {
    private const val SECONDS_PER_MINUTE = 60
    private const val MINUTES_PER_HOUR = 60
    private const val DAY_PATTERN = "EEEEMMMd"

    fun time(seconds: Double): String = DateFormat.getTimeInstance(DateFormat.SHORT).format(date(seconds))

    /** "Tuesday, Oct 27" in the viewer's locale. */
    fun day(seconds: Double): String =
        android.text.format.DateFormat.format(android.text.format.DateFormat.getBestDateTimePattern(Locale.getDefault(), DAY_PATTERN), date(seconds)).toString()

    /** "9:00 PM", "Tomorrow 9:00 PM" or "Thursday, Oct 29 9:00 PM". */
    fun dayAndTime(seconds: Double): String {
        val zone = ZoneId.systemDefault()
        val daysAway = ChronoUnit.DAYS.between(LocalDate.now(zone), Instant.ofEpochMilli((seconds * 1000).toLong()).atZone(zone).toLocalDate())
        return when (daysAway) {
            0L -> time(seconds)
            1L -> "Tomorrow ${time(seconds)}"
            else -> "${day(seconds)} ${time(seconds)}"
        }
    }

    private fun date(seconds: Double) = Date((seconds * 1000).toLong())

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
