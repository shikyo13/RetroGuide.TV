package com.adamhunt.retroguide.ui.guide

import com.adamhunt.retroguide.core.ChannelInfo
import com.adamhunt.retroguide.core.CoreClient
import com.adamhunt.retroguide.core.ProgramInfo
import com.adamhunt.retroguide.ui.watch.nowSeconds
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlin.math.floor
import kotlin.math.max

/**
 * The guide's schedule window and focus (the Apple app's `GuideModel`). Focus
 * moves program by program within a row and keeps its time across rows; the
 * window pages by half hours to keep the focused program in view.
 */
class GuideModel(
    private val core: CoreClient,
    val channels: List<ChannelInfo>,
    tunedChannelID: String?,
    private val scope: CoroutineScope,
) {
    object Time {
        /** One column of the guide (the ruler ticks). */
        const val SLOT = 30 * 60.0
        /** How many slots are visible across the grid. */
        const val VISIBLE_SLOTS = 3
        const val WINDOW = SLOT * VISIBLE_SLOTS
        /** How far into the future the guide can be browsed. */
        const val LOOKAHEAD = 24 * 3600.0
        /** When paging right, keep at least this much of the focused program visible. */
        const val MINIMUM_VISIBLE = 15 * 60.0
        /** Schedules are loaded this far ahead of the window at a time. */
        const val LOAD_SPAN = 4 * 3600.0
        /** Nudges focus anchors inside a program rather than on its boundary. */
        const val EPSILON = 1.0
    }

    sealed interface Focus {
        data class Program(val row: Int, val anchor: Double) : Focus
        /** The top bar's buttons. */
        data class Header(val index: Int) : Focus
    }

    private val _windowStart = MutableStateFlow(slotStart(nowSeconds()))
    val windowStart: StateFlow<Double> = _windowStart.asStateFlow()
    private val _schedules = MutableStateFlow<Map<String, List<ProgramInfo>>>(emptyMap())
    val schedules: StateFlow<Map<String, List<ProgramInfo>>> = _schedules.asStateFlow()
    private val _focus = MutableStateFlow<Focus>(Focus.Program(max(0, channels.indexOfFirst { it.id == tunedChannelID }), nowSeconds()))
    val focus: StateFlow<Focus> = _focus.asStateFlow()
    private var loadedUntil = 0.0
    /** The program focused last, kept while focus is in the top row (its details stay up, and Remind me acts on it). */
    private var lastProgramFocus: Focus.Program = _focus.value as Focus.Program

    init {
        load(_windowStart.value)
    }

    val focusedProgram: ProgramInfo?
        get() = (focus.value as? Focus.Program)?.let { programAt(it.row, it.anchor) }

    val focusedChannel: ChannelInfo?
        get() = (focus.value as? Focus.Program)?.let { channels.getOrNull(it.row) }

    /** The program focused now, or the one focus came up from. */
    val selectedProgram: ProgramInfo?
        get() = programAt(lastProgramFocus.row, lastProgramFocus.anchor)

    val selectedChannel: ChannelInfo?
        get() = channels.getOrNull(lastProgramFocus.row)

    /** The top row's buttons: Remind me only for an upcoming program. */
    fun headerButtons(now: Double = nowSeconds()): List<GuideHeaderButton> =
        GuideHeaderButton.entries.filter { it != GuideHeaderButton.REMINDER || (selectedProgram?.start ?: 0.0) > now }

    fun programAt(row: Int, time: Double): ProgramInfo? =
        channels.getOrNull(row)?.let { channel -> _schedules.value[channel.id]?.firstOrNull { time >= it.start && time < it.end } }

    /** Play/Pause: the shortcut to the top bar from any row. */
    fun focusHeader() {
        setFocus(Focus.Header(TOP_ROW_ENTRY))
    }

    private fun setFocus(focus: Focus) {
        if (focus is Focus.Program) lastProgramFocus = focus
        _focus.value = focus
    }

    fun moveUp() {
        when (val focus = _focus.value) {
            is Focus.Program -> setFocus(if (focus.row == 0) Focus.Header(TOP_ROW_ENTRY) else focus.copy(row = focus.row - 1))
            is Focus.Header -> Unit
        }
    }

    fun moveDown() {
        when (val focus = _focus.value) {
            is Focus.Program -> if (focus.row < channels.lastIndex) setFocus(focus.copy(row = focus.row + 1))
            // Back down to the program focus came up from.
            is Focus.Header -> setFocus(lastProgramFocus)
        }
    }

    fun moveRight(headerCount: Int) {
        when (val focus = _focus.value) {
            is Focus.Header -> setFocus(focus.copy(index = (focus.index + 1).coerceAtMost(headerCount - 1)))
            is Focus.Program -> {
                val current = programAt(focus.row, focus.anchor) ?: return
                if (current.end >= nowSeconds() + Time.LOOKAHEAD) return
                val next = programAt(focus.row, current.end + Time.EPSILON)
                val anchor = (next?.start ?: current.end) + Time.EPSILON
                setFocus(focus.copy(anchor = anchor))
                // Page right so the program now focused shows at least a little.
                val windowEnd = _windowStart.value + Time.WINDOW
                if (anchor > windowEnd - Time.MINIMUM_VISIBLE) setWindow(slotStart(anchor))
            }
        }
    }

    fun moveLeft() {
        when (val focus = _focus.value) {
            is Focus.Header -> setFocus(focus.copy(index = (focus.index - 1).coerceAtLeast(0)))
            is Focus.Program -> {
                val current = programAt(focus.row, focus.anchor) ?: return
                val earliest = slotStart(nowSeconds())
                if (current.start <= earliest) return
                val previous = programAt(focus.row, current.start - Time.EPSILON)
                val anchor = max(earliest, (previous?.start ?: current.start) + Time.EPSILON)
                setFocus(focus.copy(anchor = anchor))
                if (anchor < _windowStart.value) setWindow(max(earliest, slotStart(anchor)))
            }
        }
    }

    /** Keeps an open guide current: the window follows the clock if it's showing now. */
    fun followClock() {
        val now = nowSeconds()
        if (_windowStart.value < slotStart(now)) setWindow(slotStart(now))
        val focus = _focus.value
        if (focus is Focus.Program && focus.anchor < now) setFocus(focus.copy(anchor = now))
    }

    private fun setWindow(start: Double) {
        _windowStart.value = start
        if (start + Time.WINDOW > loadedUntil) load(start)
    }

    private fun load(from: Double) {
        val to = from + Time.LOAD_SPAN
        loadedUntil = to
        scope.launch {
            val rows = runCatching { core.guide(from - Time.SLOT, to) }.getOrNull() ?: return@launch
            _schedules.value = _schedules.value.toMutableMap().apply {
                for (row in rows) {
                    val merged = (get(row.channelID).orEmpty() + row.programs).distinctBy { it.id }.sortedBy { it.start }
                    put(row.channelID, merged)
                }
            }
        }
    }

    companion object {
        /** Up from the grid lands on Favorites, the first button in the top bar. */
        private val TOP_ROW_ENTRY = GuideHeaderButton.FAVORITES.ordinal

        fun slotStart(time: Double) = floor(time / Time.SLOT) * Time.SLOT
    }
}
