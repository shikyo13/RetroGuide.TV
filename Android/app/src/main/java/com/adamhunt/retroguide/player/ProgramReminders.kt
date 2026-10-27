package com.adamhunt.retroguide.player

import com.adamhunt.retroguide.core.CoreClient
import com.adamhunt.retroguide.core.ReminderInfo
import com.adamhunt.retroguide.core.RemindersState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlin.math.max

/**
 * Program reminders (the Apple app's `ProgramReminders` on Apple TV): they come
 * up while RetroGuide is open, when the program starts. The core keeps them.
 */
class ProgramReminders(private val core: CoreClient, private val scope: CoroutineScope) {
    private val _pending = MutableStateFlow<List<ReminderInfo>>(emptyList())
    val pending: StateFlow<List<ReminderInfo>> = _pending.asStateFlow()
    /** A reminder whose program just started. */
    private val _due = MutableStateFlow<ReminderInfo?>(null)
    val due: StateFlow<ReminderInfo?> = _due.asStateFlow()
    /** Why a reminder couldn't be set, or why some were removed. */
    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()
    private var timer: Job? = null

    fun reload() = update { core.reminders() }

    fun toggle(channelID: String, programID: String) = update { core.toggleReminder(channelID, programID) }

    fun remove(id: String) = update { core.removeReminder(id) }

    fun dismissDue() {
        _due.value = null
    }

    fun dismissMessage() {
        _message.value = null
    }

    fun isSet(channelID: String, start: Double) = _pending.value.any { it.channelID == channelID && it.start == start }

    private fun update(request: suspend () -> RemindersState) {
        scope.launch { runCatching { request() }.getOrNull()?.let(::apply) }
    }

    private fun apply(state: RemindersState) {
        _pending.value = state.pending
        state.message?.let { _message.value = it }
        state.due?.let { _due.value = it }
        arm()
    }

    /** Wakes when the next reminder's program starts. */
    private fun arm() {
        timer?.cancel()
        val next = _pending.value.firstOrNull() ?: return
        timer = scope.launch {
            delay(max(0L, (next.start * MILLIS_PER_SECOND).toLong() - System.currentTimeMillis()))
            runCatching { core.checkReminders() }.getOrNull()?.let(::apply)
        }
    }

    private companion object {
        const val MILLIS_PER_SECOND = 1000
    }
}
