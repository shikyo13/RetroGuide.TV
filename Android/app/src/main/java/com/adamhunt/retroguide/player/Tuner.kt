package com.adamhunt.retroguide.player

import com.adamhunt.retroguide.core.ChannelInfo
import com.adamhunt.retroguide.core.CoreClient
import com.adamhunt.retroguide.core.ProgramInfo
import com.adamhunt.retroguide.core.StreamInfo
import com.adamhunt.retroguide.core.TrackState
import com.adamhunt.retroguide.core.TracksInfo
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
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
 * A program can also be watched from its beginning, off the channel's clock.
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
        /** How often servers that track playback hear the position. */
        const val PROGRESS_REPORT_MS = 10_000L
    }

    private object Message {
        const val DID_NOT_START = "This program won't start. Its file may be damaged."
    }

    private object Report {
        const val STARTED = "started"
        const val PROGRESS = "progress"
        const val STOPPED = "stopped"
    }

    private object TrackKind {
        const val AUDIO = "audio"
        const val SUBTITLES = "subtitles"
    }

    /** A program watched from its beginning, and where it had got to. */
    private data class Independent(val program: ProgramInfo, val originChannelID: String, var position: Double = 0.0)

    private val _channel = MutableStateFlow<ChannelInfo?>(null)
    val channel: StateFlow<ChannelInfo?> = _channel.asStateFlow()
    private val _program = MutableStateFlow<ProgramInfo?>(null)
    val program: StateFlow<ProgramInfo?> = _program.asStateFlow()
    private val _signal = MutableStateFlow<Signal>(Signal.Off)
    val signal: StateFlow<Signal> = _signal.asStateFlow()
    private val _tracks = MutableStateFlow<TracksInfo?>(null)
    val tracks: StateFlow<TracksInfo?> = _tracks.asStateFlow()
    private val _trackState = MutableStateFlow<TrackState?>(null)
    val trackState: StateFlow<TrackState?> = _trackState.asStateFlow()
    private val _isWatchingFromBeginning = MutableStateFlow(false)
    val isWatchingFromBeginning: StateFlow<Boolean> = _isWatchingFromBeginning.asStateFlow()

    /** Channels Up and Down move through (favorites only, when that's on); all channels otherwise. */
    var surfChannelIDs: Set<String>? = null

    private var channels: List<ChannelInfo> = emptyList()
    private var previousChannelID: String? = null
    private var independent: Independent? = null
    private var tuneJob: Job? = null
    private var boundaryJob: Job? = null
    private var watchdogJob: Job? = null
    private var reportJob: Job? = null
    private var lastSurfAt: Long? = null
    private var failedAttempts = 0
    private var generation = 0
    private var activeStream: StreamInfo? = null
    /** The tune whose stream servers are hearing about, or `null`. */
    private var reportingGeneration: Int? = null

    init {
        scope.launch {
            player.events.collect { event ->
                when (event) {
                    PlayerEvent.Playing -> if (_signal.value == Signal.Tuning) {
                        watchdogJob?.cancel()
                        failedAttempts = 0
                        _signal.value = Signal.Live
                        startReporting()
                    }
                    PlayerEvent.Ended -> when {
                        independent != null -> returnToLive()
                        // The file ran shorter than its metadata; fill until the next program.
                        _signal.value == Signal.Live -> _program.value?.let { program ->
                            endActiveStream()
                            _signal.value = Signal.Intermission(program.end)
                            scheduleBoundary(program.end, generation)
                        }
                    }
                    is PlayerEvent.Failed -> fail(event.message, generation)
                }
            }
        }
    }

    fun setChannels(visible: List<ChannelInfo>) {
        channels = visible
        val current = _channel.value
        if (current != null && visible.none { it.id == current.id }) {
            visible.firstOrNull()?.let { tune(it, isAutomatic = true) }
        } else if (current != null) {
            // Keep favorites and names current.
            _channel.value = visible.firstOrNull { it.id == current.id } ?: current
        }
    }

    fun channelWithID(id: String?): ChannelInfo? = channels.firstOrNull { it.id == id }

    /** Tunes [channel]. Choosing the channel that's already playing keeps its stream. */
    fun tune(channel: ChannelInfo, surfing: Boolean = false, isAutomatic: Boolean = false) {
        val isSameChannel = channel.id == _channel.value?.id && independent == null
        if (!isAutomatic && isSameChannel && _signal.value != Signal.Off && _signal.value !is Signal.NoSignal) return
        if (channel.id != _channel.value?.id) previousChannelID = _channel.value?.id
        independent = null
        _isWatchingFromBeginning.value = false
        val now = System.currentTimeMillis()
        val isFlipping = surfing && lastSurfAt?.let { now - it < Timing.FLIPPING_WINDOW_MS } == true
        lastSurfAt = if (surfing) now else null
        val forGeneration = begin(channel)
        onChannelChanged(channel.id)
        // The banner shows the program right away, before its stream starts.
        scope.launch { nowPlaying(channel.id)?.let { if (forGeneration == generation) _program.value = it } }
        tuneJob = scope.launch {
            if (isFlipping) delay(Timing.SURF_SETTLE_MS)
            startPlayback(forGeneration)
        }
    }

    /** Plays [program] from 0:00, off its channel's clock, until it ends or the viewer returns to live. */
    fun watchFromBeginning(program: ProgramInfo) {
        val channel = _channel.value ?: return
        independent = Independent(program, channel.id)
        _isWatchingFromBeginning.value = true
        _program.value = program
        val forGeneration = begin(channel)
        tuneJob = scope.launch { startPlayback(forGeneration) }
    }

    /** Back to the channel's live program after watching from the beginning. */
    fun returnToLive() {
        val origin = independent?.originChannelID ?: return
        independent = null
        _isWatchingFromBeginning.value = false
        channelWithID(origin)?.let { tune(it, isAutomatic = true) } ?: powerOff()
    }

    fun channelUp() = step(1)
    fun channelDown() = step(-1)

    /** Jumps back to the previously watched channel (the remote's Play/Pause). */
    fun recall() {
        channelWithID(previousChannelID)?.let { tune(it) }
    }

    /** Plays [optionID] now and remembers it for [scope] (`null`: back to automatic). */
    fun chooseAudio(optionID: String?, scope: String?) = choose(TrackKind.AUDIO, optionID, scope)

    /** Shows [optionID] (`null`: off) now and remembers it for [scope] (`null`: back to automatic). */
    fun chooseSubtitles(optionID: String?, scope: String?) = choose(TrackKind.SUBTITLES, optionID, scope)

    /** Moves subtitles earlier (−1) or later (+1); 0 restores the original timing. */
    fun nudgeSubtitles(direction: Int, repeatCount: Int) {
        scope.launch {
            runCatching { core.nudgeSubtitles(direction, repeatCount) }.getOrNull()?.let { state ->
                _trackState.value = state
                player.setSubtitleDelay(state.subtitleDelay)
            }
        }
    }

    /** Stops the picture (the app went to the background, or the sleep timer ran out); [resume] rejoins. */
    fun suspend() {
        independent?.let { watching -> player.position?.let { watching.position = it } }
        generation += 1
        stopTimers()
        endActiveStream()
        player.stop()
        _signal.value = Signal.Off
    }

    /** Rejoins the channel live after [suspend] (or the program watched from the beginning, where it was). */
    fun resume() {
        if (_signal.value != Signal.Off) return
        val channel = _channel.value ?: return
        if (independent != null) {
            val forGeneration = begin(channel)
            tuneJob = scope.launch { startPlayback(forGeneration) }
        } else {
            tune(channel, isAutomatic = true)
        }
    }

    fun powerOff() {
        independent = null
        _isWatchingFromBeginning.value = false
        suspend()
    }

    private fun choose(kind: String, optionID: String?, trackScope: String?) {
        scope.launch {
            val state = runCatching { core.chooseTrack(kind, optionID, trackScope) }.getOrNull() ?: return@launch
            _trackState.value = state
            state.selection?.let(player::select)
            player.setSubtitleDelay(state.subtitleDelay)
        }
    }

    /** Stops what's playing and shows [channel] tuning; returns the new tune's generation. */
    private fun begin(channel: ChannelInfo): Int {
        _channel.value = channel
        _signal.value = Signal.Tuning
        _tracks.value = null
        _trackState.value = null
        failedAttempts = 0
        generation += 1
        stopTimers()
        endActiveStream()
        player.stop()
        return generation
    }

    private fun step(offset: Int) {
        val ring = surfChannelIDs?.let { ids -> channels.filter { it.id in ids } }?.takeIf { it.isNotEmpty() } ?: channels
        if (ring.isEmpty()) return
        val index = ring.indexOfFirst { it.id == _channel.value?.id }
        val next = if (index < 0) ring.first() else ring[Math.floorMod(index + offset, ring.size)]
        tune(next, surfing = true)
    }

    private suspend fun nowPlaying(channelID: String): ProgramInfo? {
        val now = System.currentTimeMillis() / 1000.0
        return runCatching { core.guide(now, now + 1, listOf(channelID)).firstOrNull()?.programs?.firstOrNull() }.getOrNull()
    }

    private suspend fun startPlayback(forGeneration: Int) {
        val channel = _channel.value ?: return
        if (forGeneration != generation) return
        val watching = independent
        try {
            val result = core.tune(channel.id, forGeneration, watching?.program?.id, watching?.position)
            if (forGeneration != generation) {
                result.stream?.let(::release)
                return
            }
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
            _trackState.value = result.trackState
            player.setSubtitleDelay(result.trackState?.subtitleDelay ?: 0.0)
            player.play(stream, result.trackState?.selection ?: result.tracks?.selection)
            if (watching == null) scheduleBoundary(result.program.contentEnd, forGeneration)
            watchdogJob?.cancel()
            watchdogJob = scope.launch {
                delay(Timing.START_TIMEOUT_MS)
                if (forGeneration != generation || _signal.value != Signal.Tuning) return@launch
                if (independent != null) fail(Message.DID_NOT_START, forGeneration) else waitForNextProgram(result.program, forGeneration)
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

    /** Tells servers that track playback (Jellyfin) about this stream while it plays. */
    private fun startReporting() {
        val forGeneration = generation
        reportingGeneration = forGeneration
        reportJob?.cancel()
        reportJob = scope.launch {
            runCatching { core.playbackEvent(Report.STARTED, forGeneration, player.position) }
            while (isActive && forGeneration == generation) {
                delay(Timing.PROGRESS_REPORT_MS)
                runCatching { core.playbackEvent(Report.PROGRESS, forGeneration, player.position) }
            }
        }
    }

    private fun stopTimers() {
        tuneJob?.cancel()
        boundaryJob?.cancel()
        watchdogJob?.cancel()
        reportJob?.cancel()
    }

    /** Ends playback reports and tells the server to release a repackaged stream. */
    private fun endActiveStream() {
        reportingGeneration?.let { reported ->
            reportingGeneration = null
            val position = player.position
            scope.launch { runCatching { core.playbackEvent(Report.STOPPED, reported, position) } }
        }
        activeStream?.let(::release)
        activeStream = null
    }

    private fun release(stream: StreamInfo) {
        if (stream.needsTeardown) scope.launch { runCatching { core.endStream(stream.serverID, stream.sessionID) } }
    }
}
