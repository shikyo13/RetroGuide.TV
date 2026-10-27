package com.adamhunt.retroguide

import android.app.Application
import android.content.Intent
import android.content.pm.ApplicationInfo
import com.adamhunt.retroguide.player.MpvPlayer

class RetroGuideApplication : Application() {
    private val isDebuggable get() = applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0

    /** App state for the life of the process. Debug builds on an emulator play muted, so QA stays quiet. */
    val model by lazy { AppModel(this, muted = isDebuggable && MpvPlayer.isEmulator) }

    private var isStarted = false

    /** Starts the app once; debug builds may pass a QA server (see [DevelopmentLaunch]). */
    fun start(intent: Intent) {
        if (isStarted) return
        isStarted = true
        if (isDebuggable) {
            model.start(DevelopmentLaunch.server(intent), developmentPro = DevelopmentLaunch.isPro(intent))
        } else {
            model.start()
        }
    }
}
