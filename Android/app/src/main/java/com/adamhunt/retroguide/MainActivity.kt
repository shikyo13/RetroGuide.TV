package com.adamhunt.retroguide

import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.adamhunt.retroguide.ui.RootScreen
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private val app get() = application as RetroGuideApplication

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        app.start(intent)
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
    }

    override fun onStart() {
        super.onStart()
        app.model.becameActive()
    }

    override fun onStop() {
        super.onStop()
        app.model.enteredBackground()
    }
}
