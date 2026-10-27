package com.adamhunt.retroguide.player

import com.adamhunt.retroguide.core.ChannelInfo
import com.adamhunt.retroguide.core.CoreClient
import com.adamhunt.retroguide.core.ProgramInfo
import com.adamhunt.retroguide.core.SelectionInfo
import com.adamhunt.retroguide.core.StreamInfo
import com.adamhunt.retroguide.core.TrackInfo
import com.adamhunt.retroguide.core.TracksInfo
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlin.math.max

/** What the screen shows for the tuned channel. */
sealed interface Signal {
    data object Off : Signal
    data object Tuning : Signal
    data object Live : Signal
    data class Intermission(val until: Double) : Signal
    data class NoSignal(val message: String) : Signal
}

/**
 * Channel surfing on the schedule (the Apple app's `Tuner`): tunes a channel
 * at its live position, follows the schedule from program to program,
 * retries quietly before showing No Signal, and remembers the last channel.
 */
class Tuner(
    private val core: CoreClient,
    private val player: MpvPlayer,
    private val scope: CoroutineScope,
    private val onChannelChanged: (String) -> Unit,
) {
    private object Timing {
        /** While flipping, wait this long after each press before starting a stream. */
        const val SURF_SETTLE_MS = 450L
        /** Presses closer together than this count as flipping. */
        const val FLIPPING_WINDOW_MS = 1_000L
        /** Quiet retries behind the tuning static before showing No Signal. */
        val QUICK_RETRY_DELAYS_MS = listOf(1_000L, 2_000L, 4_000L)
        /** After quick retries are exhausted, keep retrying at this interval. */
        const val RETRY_DELAY_MS = 15_000L
        /** A program not playing this long after its stream opened won't start. */
        const val START_TIMEOUT_MS = 30_000L
    }

    private object Message {
        const val DID_NOT_START = "This program won't start. Its file may be damaged."
    }

    private val _channel = MutableStateFlow<ChannelInfo?>(null)
    val channel: StateFlow<ChannelInfo?> = _channel.asStateFlow()
    private val _program = MutableStateFlow<ProgramInfo?>(null)
    val program: StateFlow<ProgramInfo?> = _program.asStateFlow()
    private val _signal = MutableStateFlow<Signal>(Signal.Off)
    val signal: StateFlow<Signal> = _signal.asStateFlow()
    private val _tracks = MutableStateFlow<TracksInfo?>(null)
    val tracks: StateFlow<TracksInfo?> = _tracks.asStateFlow()
    private val _selection = MutableStateFlow<SelectionInfo?>(null)
    val selection: StateFlow<SelectionInfo?> = _selection.asStateFlow()

    private var channels: List<ChannelInfo> = emptyList()
    private var previousChannelID: String? = null
    private var tuneJob: Job? = null
    private var boundaryJob: Job? = null
    private var watchdogJob: Job? = null
    private var lastSurfAt: Long? = null
    private var failedAttempts = 0
    private var generation = 0
    private var activeStream: StreamInfo? = null

    init {
        scope.launch {
            player.events.collectLatest { event ->
                when (event) {
                    PlayerEvent.Playing -> if (_signal.value == Signal.Tuning) {
                        watchdogJob?.cancel()
                        failedAttempts = 0
                        _signal.value = Signal.Live
                    }
                    // The file ran shorter than its metadata; fill until the next program.
                    PlayerEvent.Ended -> _program.value?.let { program ->
                        if (_signal.value == Signal.Live) {
                            endActiveStream()
                            _signal.value = Signal.Intermission(program.end)
                            scheduleBoundary(program.end, generation)
                        }
                    }
                    is PlayerEvent.Failed -> fail(event.message, generation)
                    null -> Unit
                }
            }
        }
    }

    fun setChannels(visible: List<ChannelInfo>) {
        channels = visible
        val current = _channel.value
        if (current != null && visible.none { it.id == current.id }) {
            visible.firstOrNull()?.let { tune(it, isAutomatic = true) }
        }
    }

    fun channelWithID(id: String?): ChannelInfo? = channels.firstOrNull { it.id == id }

    /** Tunes [channel]. Choosing the channel that's already playing keeps its stream. */
    fun tune(channel: ChannelInfo, surfing: Boolean = false, isAutomatic: Boolean = false) {
        if (!isAutomatic && channel.id == _channel.value?.id && _signal.value != Signal.Off && _signal.value !is Signal.NoSignal) return
        if (channel.id != _channel.value?.id) previousChannelID = _channel.value?.id
        _channel.value = channel
        _signal.value = Signal.Tuning
        _tracks.value = null
        _selection.value = null
        failedAttempts = 0
        generation += 1
        val forGeneration = generation
        onChannelChanged(channel.id)
        stopTimers()
        endActiveStream()
        player.stop()
        val now = System.currentTimeMillis()
        val isFlipping = surfing && lastSurfAt?.let { now - it < Timing.FLIPPING_WINDOW_MS } == true
        lastSurfAt = if (surfing) now else null
        // The banner shows the program right away, before its stream starts.
        scope.launch { nowPlaying(channel.id)?.let { if (forGeneration == generation) _program.value = it } }
        tuneJob = scope.launch {
            if (isFlipping) delay(Timing.SURF_SETTLE_MS)
            startPlayback(forGeneration)
        }
    }

    fun channelUp() = step(1)
    fun channelDown() = step(-1)

    /** Jumps back to the previously watched channel (the remote's Play/Pause). */
    fun recall() {
        channelWithID(previousChannelID)?.let { tune(it) }
    }

    fun chooseAudio(track: TrackInfo) {
        val selection = _selection.value ?: return
        _selection.value = selection.withAudio(track)
        player.select(_selection.value!!)
    }

    fun chooseSubtitles(track: TrackInfo?) {
        val selection = _selection.value ?: return
        _selection.value = selection.withSubtitle(track)
        player.select(_selection.value!!)
    }

    fun powerOff() {
        generation += 1
        stopTimers()
        endActiveStream()
        player.stop()
        _signal.value = Signal.Off
    }

    private fun step(offset: Int) {
        if (channels.isEmpty()) return
        val index = channels.indexOfFirst { it.id == _channel.value?.id }.coerceAtLeast(0)
        tune(channels[Math.floorMod(index + offset, channels.size)], surfing = true)
    }

    private suspend fun nowPlaying(channelID: String): ProgramInfo? {
        val now = System.currentTimeMillis() / 1000.0
        return runCatching { core.guide(now, now + 1, listOf(channelID)).firstOrNull()?.programs?.firstOrNull() }.getOrNull()
    }

    private suspend fun startPlayback(forGeneration: Int) {
        val channel = _channel.value ?: return
        if (forGeneration != generation) return
        try {
            val result = core.tune(channel.id)
            if (forGeneration != generation) return
            _program.value = result.program
            val intermission = result.intermissionUntil
            val stream = result.stream
            if (intermission != null || stream == null) {
                player.stop()
                _signal.value = Signal.Intermission(intermission ?: result.program.end)
                scheduleBoundary(intermission ?: result.program.end, forGeneration)
                return
            }
            if (_signal.value !is Signal.NoSignal) _signal.value = Signal.Tuning
            activeStream = stream
            _tracks.value = result.tracks
            _selection.value = result.tracks?.selection
            player.play(stream, result.tracks?.selection)
            scheduleBoundary(result.program.contentEnd, forGeneration)
            watchdogJob?.cancel()
            watchdogJob = scope.launch {
                delay(Timing.START_TIMEOUT_MS)
                if (forGeneration == generation && _signal.value == Signal.Tuning) waitForNextProgram(result.program, forGeneration)
            }
        } catch (error: Exception) {
            if (forGeneration == generation) fail(error.message ?: "The channel can't be tuned.", forGeneration)
        }
    }

    /** Gives up on a program that won't start and waits for the next one. */
    private fun waitForNextProgram(program: ProgramInfo, forGeneration: Int) {
        endActiveStream()
        player.stop()
        _signal.value = Signal.NoSignal(Message.DID_NOT_START)
        scheduleBoundary(program.end, forGeneration)
    }

    /** Sleeps until [time] (seconds), then follows the schedule. */
    private fun scheduleBoundary(time: Double, forGeneration: Int) {
        boundaryJob?.cancel()
        boundaryJob = scope.launch {
            delay(max(0L, (time * 1000).toLong() - System.currentTimeMillis()))
            if (forGeneration != generation) return@launch
            endActiveStream()
            _signal.value = Signal.Tuning
            startPlayback(forGeneration)
        }
    }

    private fun fail(message: String, forGeneration: Int) {
        watchdogJob?.cancel()
        endActiveStream()
        player.stop()
        boundaryJob?.cancel()
        val quick = Timing.QUICK_RETRY_DELAYS_MS.getOrNull(failedAttempts)
        _signal.value = if (quick != null) Signal.Tuning else Signal.NoSignal(message)
        failedAttempts += 1
        boundaryJob = scope.launch {
            delay(quick ?: Timing.RETRY_DELAY_MS)
            if (forGeneration == generation) startPlayback(forGeneration)
        }
    }

    private fun stopTimers() {
        tuneJob?.cancel()
        boundaryJob?.cancel()
        watchdogJob?.cancel()
    }

    /** Tells the server to release a repackaged stream. */
    private fun endActiveStream() {
        val stream = activeStream ?: return
        activeStream = null
        if (stream.needsTeardown) scope.launch { runCatching { core.endStream(stream.serverID, stream.sessionID) } }
    }
}
