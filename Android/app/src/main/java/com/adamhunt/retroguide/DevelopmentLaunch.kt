package com.adamhunt.retroguide

import android.content.Intent
import com.adamhunt.retroguide.core.CoreClient

/**
 * QA launch options for debug builds (the Apple app's `DebugBootstrap`):
 * `am start -n com.adamhunt.retroguide/.MainActivity --es devServerURL … --es devServerToken …`
 * adds that server without signing in. Release builds never read them.
 */
object DevelopmentLaunch {
    private object Extra {
        const val ID = "devServerID"
        const val KIND = "devServerKind"
        const val NAME = "devServerName"
        const val URL = "devServerURL"
        const val TOKEN = "devServerToken"
        const val USER_ID = "devServerUserID"
        const val ACCOUNT_TOKEN = "devPlexAccountToken"
        const val DEFAULT_KIND = "plex"
    }

    fun server(intent: Intent): CoreClient.DevelopmentServer? {
        val id = intent.getStringExtra(Extra.ID) ?: return null
        val url = intent.getStringExtra(Extra.URL) ?: return null
        val token = intent.getStringExtra(Extra.TOKEN) ?: return null
        return CoreClient.DevelopmentServer(
            id = id,
            kind = intent.getStringExtra(Extra.KIND) ?: Extra.DEFAULT_KIND,
            name = intent.getStringExtra(Extra.NAME) ?: id,
            address = url,
            token = token,
            userID = intent.getStringExtra(Extra.USER_ID),
            accountToken = intent.getStringExtra(Extra.ACCOUNT_TOKEN),
        )
    }
}
