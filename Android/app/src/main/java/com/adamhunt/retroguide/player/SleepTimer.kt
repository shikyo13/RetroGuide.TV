package com.adamhunt.retroguide.player

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlin.math.max

/** Stops playback at a chosen time (the Apple app's `SleepTimer`). Times are seconds since 1970. */
class SleepTimer(private val scope: CoroutineScope, private val onExpire: () -> Unit) {
    /** The Kit's `SleepDeadline` choices. */
    object Choices {
        val PRESET_MINUTES = listOf(15, 30, 60, 90)
        val CUSTOM_MINUTES = 1..240
        const val DEFAULT_CUSTOM_MINUTES = 45
        const val SECONDS_PER_MINUTE = 60.0
    }

    private val _deadline = MutableStateFlow<Double?>(null)
    val deadline: StateFlow<Double?> = _deadline.asStateFlow()
    private val _didExpire = MutableStateFlow(false)
    val didExpire: StateFlow<Boolean> = _didExpire.asStateFlow()
    private var job: Job? = null

    fun start(minutes: Int) = startUntil(System.currentTimeMillis() / 1000.0 + minutes * Choices.SECONDS_PER_MINUTE)

    fun startUntil(time: Double) {
        cancel()
        _deadline.value = time
        job = scope.launch {
            delay(max(0L, (time * 1000).toLong() - System.currentTimeMillis()))
            job = null
            _deadline.value = null
            _didExpire.value = true
            onExpire()
        }
    }

    fun cancel() {
        job?.cancel()
        job = null
        _deadline.value = null
        _didExpire.value = false
    }

    fun resumeWatching() {
        _didExpire.value = false
    }
}
