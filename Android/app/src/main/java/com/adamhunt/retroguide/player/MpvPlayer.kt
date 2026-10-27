package com.adamhunt.retroguide.player

import android.content.Context
import android.os.Build
import android.view.Surface
import com.adamhunt.retroguide.core.CoreClient
import com.adamhunt.retroguide.core.SelectionInfo
import com.adamhunt.retroguide.core.StreamInfo
import dev.jdtech.mpv.MPVLib
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.security.MessageDigest

/** What the player is doing, for the tuner. */
sealed interface PlayerEvent {
    data object Playing : PlayerEvent
    data object Ended : PlayerEvent
    data class Failed(val message: String) : PlayerEvent
}

/**
 * The RetroGuide Player on Android: libmpv, configured like the Apple app's
 * (`MPVCore`): direct play of any file, certificates checked against a
 * bundled CA list, a bounded network cache, and the server's track choice
 * applied once the file has loaded. Muted when [muted] (simulator-style QA).
 */
class MpvPlayer(
    private val context: Context,
    private val core: CoreClient,
    private val muted: Boolean,
) : MPVLib.EventObserver {
    private object Option {
        val values = listOf(
            "profile" to "fast",
            "vo" to "gpu",
            "gpu-context" to "android",
            "ao" to "audiotrack",
            "cache" to "yes",
            "network-timeout" to "10",
            // Join a channel at the keyframe before the live position: starts sooner.
            "hr-seek" to "no",
            // Fallback only: the server's per-user track selection overrides these.
            "subs-match-os-language" to "yes",
            "subs-fallback" to "no",
            "subs-fallback-forced" to "yes",
            "subs-with-matching-audio" to "forced",
            // libass draws subtitles with Android's own fonts.
            "sub-fonts-dir" to "/system/fonts",
            "osd-fonts-dir" to "/system/fonts",
            "sub-font" to "Roboto",
            "idle" to "yes",
            "keep-open" to "no",
            "input-default-bindings" to "no",
            "ytdl" to "no",
            "tls-verify" to "yes",
        )
        const val CA_FILE = "cacert.pem"
        const val SUBTITLE_FOLDER = "subtitles"
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val http = OkHttpClient()
    private val _events = MutableStateFlow<PlayerEvent?>(null)
    val events: StateFlow<PlayerEvent?> = _events.asStateFlow()

    private var pendingSelection: SelectionInfo? = null
    private var subtitleDownload: Job? = null
    private var hasStartedPlaying = false
    private var generation = 0

    init {
        MPVLib.create(context)
        for ((name, value) in Option.values) MPVLib.setOptionString(name, value)
        // The emulator's MediaCodec stalls in copy mode; devices decode in hardware.
        MPVLib.setOptionString("hwdec", if (isEmulator) "no" else "mediacodec-copy")
        MPVLib.setOptionString("tls-ca-file", certificateAuthorities().path)
        MPVLib.setOptionString("mute", if (muted) "yes" else "no")
        MPVLib.setOptionString("force-window", "no")
        MPVLib.init()
        MPVLib.addObserver(this)
    }

    fun attach(surface: Surface) {
        MPVLib.attachSurface(surface)
        MPVLib.setOptionString("force-window", "yes")
        MPVLib.setPropertyString("vo", "gpu")
    }

    fun resize(width: Int, height: Int) {
        MPVLib.setPropertyString("android-surface-size", "${width}x$height")
    }

    fun detach() {
        MPVLib.setPropertyString("vo", "null")
        MPVLib.setOptionString("force-window", "no")
        MPVLib.detachSurface()
    }

    /** Plays [stream] from its live position; [selection] is applied once the file loads. */
    fun play(stream: StreamInfo, selection: SelectionInfo?) {
        generation += 1
        hasStartedPlaying = false
        subtitleDownload?.cancel()
        _events.value = null
        pendingSelection = selection
        MPVLib.setPropertyString("demuxer-max-bytes", stream.maxBytes)
        MPVLib.setPropertyString("demuxer-readahead-secs", stream.readaheadSeconds)
        MPVLib.setPropertyString("pause", "no")
        MPVLib.command(arrayOf("loadfile", stream.url, "replace", "-1", "start=${"%.1f".format(stream.position)}"))
    }

    /** Switches tracks on the file that's playing. */
    fun select(selection: SelectionInfo) {
        if (!hasStartedPlaying) {
            pendingSelection = selection
            return
        }
        apply(selection)
    }

    fun stop() {
        generation += 1
        subtitleDownload?.cancel()
        pendingSelection = null
        MPVLib.command(arrayOf("stop"))
    }

    // MARK: Tracks

    /**
     * Applies [selection]. A sidecar subtitle file is downloaded first and
     * added when it arrives, so a slow server never holds up the picture.
     */
    private fun apply(selection: SelectionInfo) {
        val external = selection.subtitleURL
        val now = if (external != null && selection.subtitle == SelectionInfo.EXTERNAL) selection.withSubtitle(null) else selection
        runCommands(now)
        if (external != null && selection.subtitle == SelectionInfo.EXTERNAL) {
            val forGeneration = generation
            subtitleDownload = scope.launch {
                val file = withContext(Dispatchers.IO) { runCatching { download(external) }.getOrNull() } ?: return@launch
                if (forGeneration != generation) return@launch
                runCommands(SelectionInfo(audioStreamIndex = null, subtitle = SelectionInfo.EXTERNAL, subtitleURL = "file://${file.path}"))
            }
        }
    }

    private fun runCommands(selection: SelectionInfo) {
        val trackList = MPVLib.getPropertyString("track-list") ?: return
        scope.launch {
            val commands = runCatching { core.trackCommands(selection, trackList) }.getOrDefault(emptyList())
            for (command in commands) MPVLib.command(command.toTypedArray())
        }
    }

    private fun download(url: String): File {
        val folder = File(context.cacheDir, Option.SUBTITLE_FOLDER).apply { mkdirs() }
        val name = MessageDigest.getInstance("SHA-256").digest(url.toByteArray()).joinToString("") { "%02x".format(it) }
        val extension = url.substringBefore('?').substringAfterLast('.', "srt").take(4)
        val file = File(folder, "$name.$extension")
        if (file.exists()) return file
        http.newCall(Request.Builder().url(url).build()).execute().use { response ->
            check(response.isSuccessful) { "subtitle download failed: ${response.code}" }
            file.outputStream().use { output -> response.body.byteStream().copyTo(output) }
        }
        return file
    }

    // MARK: Events

    override fun event(eventId: Int) {
        scope.launch {
            when (eventId) {
                MPVLib.MPV_EVENT_FILE_LOADED -> pendingSelection?.let {
                    pendingSelection = null
                    hasStartedPlaying = true
                    apply(it)
                }
                MPVLib.MPV_EVENT_PLAYBACK_RESTART -> {
                    hasStartedPlaying = true
                    _events.value = PlayerEvent.Playing
                }
                MPVLib.MPV_EVENT_END_FILE -> if (_events.value == PlayerEvent.Playing) {
                    _events.value = PlayerEvent.Ended
                }
            }
        }
    }

    override fun eventProperty(property: String) {}
    override fun eventProperty(property: String, value: Long) {}
    override fun eventProperty(property: String, value: Double) {}
    override fun eventProperty(property: String, value: Boolean) {}
    override fun eventProperty(property: String, value: String) {}

    /** FFmpeg's TLS can't read Android's trust store, so it checks against a bundled copy of Mozilla's. */
    private fun certificateAuthorities(): File {
        val file = File(context.filesDir, Option.CA_FILE)
        if (!file.exists()) context.assets.open(Option.CA_FILE).use { input -> file.outputStream().use(input::copyTo) }
        return file
    }

    companion object {
        val isEmulator: Boolean
            get() = Build.HARDWARE.contains("ranchu") || Build.HARDWARE.contains("goldfish") || Build.PRODUCT.contains("sdk")
    }
}
