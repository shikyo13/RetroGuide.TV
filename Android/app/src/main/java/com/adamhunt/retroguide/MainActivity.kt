package com.adamhunt.retroguide

import android.app.Activity
import android.os.Bundle
import android.util.Log
import android.view.SurfaceHolder
import android.view.SurfaceView
import dev.jdtech.mpv.MPVLib
import java.io.File

/**
 * Playback check: plays the `url` extra (from `am start`) with libmpv, muted unless `mute=false`.
 */
class MainActivity : Activity(), SurfaceHolder.Callback, MPVLib.EventObserver, MPVLib.LogObserver {
    private lateinit var surface: SurfaceView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        surface = SurfaceView(this)
        setContentView(surface)
        surface.holder.addCallback(this)

        MPVLib.create(this)
        MPVLib.setOptionString("vo", "gpu")
        MPVLib.setOptionString("gpu-context", "android")
        MPVLib.setOptionString("hwdec", intent.getStringExtra("hwdec") ?: "auto-safe")
        MPVLib.setOptionString("tls-verify", "yes")
        MPVLib.setOptionString("tls-ca-file", certificateAuthorities().path)
        MPVLib.setOptionString("mute", if (intent.getBooleanExtra("mute", true)) "yes" else "no")
        MPVLib.setOptionString("force-window", "no")
        MPVLib.init()
        MPVLib.addObserver(this)
        MPVLib.addLogObserver(this)
        MPVLib.observeProperty("time-pos", MPVLib.MPV_FORMAT_DOUBLE)
    }

    /** FFmpeg's TLS can't read Android's trust store, so it checks against a bundled copy of Mozilla's. */
    private fun certificateAuthorities(): File {
        val file = File(filesDir, "cacert.pem")
        if (!file.exists()) assets.open("cacert.pem").use { input -> file.outputStream().use(input::copyTo) }
        return file
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        MPVLib.attachSurface(holder.surface)
        MPVLib.setOptionString("force-window", "yes")
        MPVLib.setPropertyString("vo", "gpu")
        intent.getStringExtra("url")?.let { url ->
            intent.getStringExtra("start")?.let { MPVLib.setOptionString("start", it) }
            MPVLib.command(arrayOf("loadfile", url))
        }
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        MPVLib.setPropertyString("android-surface-size", "${width}x$height")
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        MPVLib.setPropertyString("vo", "null")
        MPVLib.setOptionString("force-window", "no")
        MPVLib.detachSurface()
    }

    override fun onDestroy() {
        MPVLib.removeObserver(this)
        MPVLib.removeLogObserver(this)
        MPVLib.destroy()
        super.onDestroy()
    }

    override fun eventProperty(property: String) {}
    override fun eventProperty(property: String, value: Long) {}
    override fun eventProperty(property: String, value: Boolean) {}
    override fun eventProperty(property: String, value: String) {}
    override fun eventProperty(property: String, value: Double) {
        if (property == "time-pos" && value.toLong() % 5 == 0L) Log.i(TAG, "time-pos $value")
    }

    override fun event(eventId: Int) {
        Log.i(TAG, "event $eventId")
    }

    override fun logMessage(prefix: String, level: Int, text: String) {
        if (level <= MPVLib.MPV_LOG_LEVEL_INFO) Log.i(TAG, "[$prefix] ${text.trimEnd()}")
    }

    private companion object {
        const val TAG = "RetroGuidePlayer"
    }
}
