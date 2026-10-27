package com.adamhunt.retroguide

import android.content.Context
import com.adamhunt.retroguide.core.ChannelInfo
import com.adamhunt.retroguide.core.CoreClient
import com.adamhunt.retroguide.core.CoreLauncher
import com.adamhunt.retroguide.core.ProgressInfo
import com.adamhunt.retroguide.core.ServerInfo
import com.adamhunt.retroguide.core.ServersChange
import com.adamhunt.retroguide.core.TokenVault
import com.adamhunt.retroguide.player.MpvPlayer
import com.adamhunt.retroguide.player.Tuner
import com.adamhunt.retroguide.ui.theme.ThemeId
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** The app's top-level phases (the Apple app's `AppModel.Phase`). */
sealed interface Phase {
    data object Launching : Phase
    data object Onboarding : Phase
    data class Indexing(val progress: ProgressInfo) : Phase
    data object Ready : Phase
    data class Failed(val message: String) : Phase
}

/**
 * App state: servers, lineup and the tuner, kept for the life of the process.
 * Cached libraries go on air at once and refresh in the background, as on Apple TV.
 */
class AppModel(context: Context, muted: Boolean) {
    private object Refresh {
        const val PROGRESS_POLL_MS = 400L
    }

    private object Saved {
        const val PREFERENCES = "watching"
        const val LAST_CHANNEL = "lastChannelID"
        const val THEME = "theme"
    }

    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val vault = TokenVault(appContext)
    private val preferences = appContext.getSharedPreferences(Saved.PREFERENCES, Context.MODE_PRIVATE)

    val core = CoreClient()
    val player = MpvPlayer(appContext, core, muted)
    val tuner = Tuner(core, player, scope) { channelID ->
        preferences.edit().putString(Saved.LAST_CHANNEL, channelID).apply()
    }

    private val _phase = MutableStateFlow<Phase>(Phase.Launching)
    val phase: StateFlow<Phase> = _phase.asStateFlow()
    private val _channels = MutableStateFlow<List<ChannelInfo>>(emptyList())
    val channels: StateFlow<List<ChannelInfo>> = _channels.asStateFlow()
    private val _servers = MutableStateFlow<List<ServerInfo>>(emptyList())
    val servers: StateFlow<List<ServerInfo>> = _servers.asStateFlow()
    /** Servers that couldn't be read at the last refresh. */
    private val _offline = MutableStateFlow<List<String>>(emptyList())
    val offline: StateFlow<List<String>> = _offline.asStateFlow()

    private val _themeID = MutableStateFlow(
        preferences.getString(Saved.THEME, null)?.let { saved -> ThemeId.entries.firstOrNull { it.name == saved } } ?: ThemeId.CLASSIC_CABLE,
    )
    val themeID: StateFlow<ThemeId> = _themeID.asStateFlow()

    /** RetroGuide Pro (Google Play billing isn't connected yet). */
    val isPro = false

    private var refreshJob: Job? = null

    fun setTheme(id: ThemeId) {
        _themeID.value = id
        preferences.edit().putString(Saved.THEME, id.name).apply()
    }

    fun removeServer(serverID: String) {
        scope.launch {
            runCatching { core.removeServer(serverID) }.getOrNull()?.let { change ->
                tuner.powerOff()
                _channels.value = emptyList()
                serversChanged(change)
                if (change.servers.isNotEmpty()) {
                    reloadChannels()
                    goOnAir()
                }
            }
        }
    }

    /** Removes every server and starts over at onboarding. */
    fun signOut() {
        scope.launch {
            for (server in _servers.value) runCatching { core.removeServer(server.id) }.getOrNull()?.let(::serversChanged)
        }
    }

    /** [development]: debug builds only, a server to add if it isn't connected yet. */
    fun start(development: CoreClient.DevelopmentServer? = null) {
        scope.launch {
            try {
                val started = CoreLauncher.start(appContext, core, vault.load())
                _servers.value = started.servers
                if (development != null && started.servers.none { it.id == development.id }) {
                    serversChanged(core.addDevelopmentServer(development))
                    return@launch
                }
                when {
                    started.servers.isEmpty() -> _phase.value = Phase.Onboarding
                    started.channelCount > 0 -> {
                        reloadChannels()
                        goOnAir()
                        refresh(showsProgress = false)
                    }
                    else -> refresh(showsProgress = true)
                }
            } catch (error: Exception) {
                _phase.value = Phase.Failed(error.message ?: "RetroGuide.TV couldn't start.")
            }
        }
    }

    /** Servers were added during onboarding or from Settings: keep their tokens, then index. */
    fun serversChanged(change: ServersChange) {
        vault.save(change.tokens)
        _servers.value = change.servers
        if (change.servers.isEmpty()) {
            tuner.powerOff()
            _channels.value = emptyList()
            _phase.value = Phase.Onboarding
            return
        }
        refresh(showsProgress = _channels.value.isEmpty())
    }

    fun retry() = refresh(showsProgress = true)

    /** Reads every server again and rebuilds the lineup. */
    fun refresh(showsProgress: Boolean) {
        refreshJob?.cancel()
        refreshJob = scope.launch {
            val poll = if (showsProgress) launch {
                _phase.value = Phase.Indexing(ProgressInfo(0.0, "Connecting…"))
                while (isActive) {
                    runCatching { core.progress() }.getOrNull()?.let { _phase.value = Phase.Indexing(it) }
                    delay(Refresh.PROGRESS_POLL_MS)
                }
            } else null
            try {
                val result = core.refresh()
                poll?.cancel()
                _offline.value = result.offlineServers
                _servers.value = core.servers()
                reloadChannels()
                goOnAir()
            } catch (error: Exception) {
                poll?.cancel()
                if (showsProgress) _phase.value = Phase.Failed(error.message ?: "Couldn't read your library.")
            }
        }
    }

    private suspend fun reloadChannels() {
        val visible = core.channels().filter { !it.isHidden }
        _channels.value = visible
        tuner.setChannels(visible)
    }

    /** Powers the "TV" on to the last watched channel (or the first one). */
    private fun goOnAir() {
        if (_phase.value != Phase.Ready) _phase.value = Phase.Ready
        if (tuner.channel.value != null) return
        val last = tuner.channelWithID(preferences.getString(Saved.LAST_CHANNEL, null))
        (last ?: _channels.value.firstOrNull())?.let { tuner.tune(it, isAutomatic = true) }
    }
}
