package com.adamhunt.retroguide

import android.Manifest
import android.app.PictureInPictureParams
import android.os.Build
import androidx.activity.result.contract.ActivityResultContracts
import android.content.Intent
import android.content.res.Configuration
import android.util.Rational
import com.adamhunt.retroguide.player.Signal
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.adamhunt.retroguide.ui.RootScreen
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import com.adamhunt.retroguide.player.DisplayModeMatcher

class MainActivity : ComponentActivity() {
    private val app get() = application as RetroGuideApplication
    private val notificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { isGranted ->
        app.model.reminders.permissionAnswered(isGranted)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        app.start(intent)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            app.model.reminders.onNeedsPermission = { notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS) }
        }
        // Live TV keeps the screen on, until the sleep timer stops it.
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                app.model.sleepTimer.didExpire.collect { didExpire ->
                    if (didExpire) {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                }
            }
        }
        // Match TV mode: the refresh rate follows what's playing.
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                combine(app.model.player.frameRate, app.model.matchTVMode) { rate, mode -> rate to mode }.collect { (rate, mode) ->
                    DisplayModeMatcher.apply(window, rate, mode)
                }
            }
        }
        setContent { RootScreen(app.model) }
        openLink(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        openLink(intent)
    }

    /** `retroguide://channel?id=…` tunes that channel. */
    private fun openLink(intent: Intent) {
        val link = intent.data ?: return
        if (link.scheme == LINK_SCHEME && link.host == LINK_CHANNEL) link.getQueryParameter(LINK_ID)?.let(app.model::openChannel)
    }

    private companion object {
        const val LINK_SCHEME = "retroguide"
        const val LINK_CHANNEL = "channel"
        const val LINK_ID = "id"
        const val PICTURE_WIDTH = 16
        const val PICTURE_HEIGHT = 9
    }

    /** Phones and tablets: leaving the app while a channel plays keeps it in a Picture in Picture window. */
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (app.model.formFactor.isTouch && app.model.tuner.signal.value != Signal.Off) {
            runCatching { enterPictureInPictureMode(pictureInPictureParams()) }
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        app.model.setPictureInPicture(isInPictureInPictureMode)
    }

    private fun pictureInPictureParams(): PictureInPictureParams =
        PictureInPictureParams.Builder()
            .setAspectRatio(Rational(PICTURE_WIDTH, PICTURE_HEIGHT))
            .setSeamlessResizeEnabled(true)
            .build()

    override fun onStart() {
        super.onStart()
        app.model.becameActive()
    }

    override fun onStop() {
        super.onStop()
        app.model.enteredBackground()
    }
}
