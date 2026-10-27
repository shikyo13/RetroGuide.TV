package com.adamhunt.retroguide

import android.content.Context
import android.content.pm.PackageManager
import com.adamhunt.retroguide.ui.FormFactor
import com.adamhunt.retroguide.core.ChannelDraft
import com.adamhunt.retroguide.core.ChannelInfo
import com.adamhunt.retroguide.core.ParentalDraft
import com.adamhunt.retroguide.core.ParentalLock
import com.adamhunt.retroguide.core.CoreClient
import com.adamhunt.retroguide.core.CoreLauncher
import com.adamhunt.retroguide.core.ProgressInfo
import com.adamhunt.retroguide.core.ServerInfo
import com.adamhunt.retroguide.core.ServersChange
import com.adamhunt.retroguide.core.TokenVault
import com.adamhunt.retroguide.home.HomeScreenRow
import com.adamhunt.retroguide.core.NetworkMonitor
import com.adamhunt.retroguide.player.MatchTVMode
import com.adamhunt.retroguide.player.MpvPlayer
import com.adamhunt.retroguide.player.ProgramReminders
import com.adamhunt.retroguide.player.SleepTimer
import com.adamhunt.retroguide.player.Tuner
import com.adamhunt.retroguide.ui.onboarding.OnboardingModel
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
        /** Re-index in the background when the cache is older than this. */
        const val STALE_AFTER_SECONDS = 6 * 3600.0
        /** How often server reachability is re-checked while the app is open. */
        const val HEALTH_CHECK_MS = 10 * 60 * 1000L
    }

    private object Saved {
        const val PREFERENCES = "watching"
        const val LAST_CHANNEL = "lastChannelID"
        const val THEME = "theme"
        const val MATCH_TV_MODE = "matchTVMode"
        const val SCANLINES = "showsScanlines"
    }

    private val appContext = context.applicationContext

    /** Android TV (remote) or a phone or tablet (touch). */
    val formFactor: FormFactor =
        if (context.packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)) FormFactor.TV else FormFactor.TOUCH
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val vault = TokenVault(appContext)
    private val network = NetworkMonitor(appContext)
    private val homeRow = HomeScreenRow(appContext)
    private var homeRowJob: Job? = null
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

    private val _matchTVMode = MutableStateFlow(
        preferences.getString(Saved.MATCH_TV_MODE, null)?.let { saved -> MatchTVMode.entries.firstOrNull { it.name == saved } } ?: MatchTVMode.OFF,
    )
    val matchTVMode: StateFlow<MatchTVMode> = _matchTVMode.asStateFlow()

    /** CRT scanlines on menus (on unless turned off, as on Apple platforms). */
    private val _showsScanlines = MutableStateFlow(preferences.getBoolean(Saved.SCANLINES, true))
    val showsScanlines: StateFlow<Boolean> = _showsScanlines.asStateFlow()

    fun setShowsScanlines(isOn: Boolean) {
        _showsScanlines.value = isOn
        preferences.edit().putBoolean(Saved.SCANLINES, isOn).apply()
    }

    fun setMatchTVMode(mode: MatchTVMode) {
        _matchTVMode.value = mode
        preferences.edit().putString(Saved.MATCH_TV_MODE, mode.name).apply()
    }

    /** RetroGuide Pro. Google Play Billing isn't connected yet; debug builds can turn it on for QA. */
    private val _isPro = MutableStateFlow(false)
    val isPro: StateFlow<Boolean> = _isPro.asStateFlow()

    /** Guide and channel surfing show only favorites (a Pro feature). */
    private val _favoritesOnly = MutableStateFlow(false)
    val favoritesOnly: StateFlow<Boolean> = _favoritesOnly.asStateFlow()

    val sleepTimer = SleepTimer(scope) { tuner.suspend() }
    val reminders = ProgramReminders(core, scope)

    private var refreshJob: Job? = null
    private var isInBackground = false
    private val _isRefreshing = MutableStateFlow(false)
    val isRefreshing: StateFlow<Boolean> = _isRefreshing.asStateFlow()

    /** The channels the guide shows: favorites only when that's on. */
    fun browsingChannels(): List<ChannelInfo> {
        val visible = _channels.value
        if (!(_isPro.value && _favoritesOnly.value)) return visible
        return visible.filter { it.isFavorite }.ifEmpty { visible }
    }

    fun setPro(isPro: Boolean) {
        _isPro.value = isPro
        scope.launch { runCatching { core.setPro(isPro) } }
        updateSurfing()
    }

    fun toggleFavorite(channelID: String) = changeLineup { core.toggleFavorite(channelID) }

    fun setFavoritesOnly(isOn: Boolean) {
        scope.launch {
            runCatching { core.setFavoritesOnly(isOn) }.getOrNull()?.let { _favoritesOnly.value = it.favoritesOnly }
            updateSurfing()
        }
    }

    fun setOrdering(channelID: String, ordering: String) = changeLineup { core.setOrdering(channelID, ordering) }
    fun removeTitle(channelID: String, showID: String) = changeLineup { core.removeTitle(channelID, showID) }
    fun restoreTitle(channelID: String, showID: String) = changeLineup { core.restoreTitle(channelID, showID) }
    fun setHidden(channelID: String, isHidden: Boolean) = changeLineup { core.setHidden(channelID, isHidden) }

    fun setSource(source: String, isEnabled: Boolean) = changeLineup { core.setSource(source, isEnabled) }
    fun setSimulcastLimit(limit: String) = changeLineup { core.setSimulcastLimit(limit) }
    fun setOrderingForAllChannels(ordering: String?) = changeLineup { core.setOrderingForAllChannels(ordering) }
    fun saveCustomChannel(draft: ChannelDraft) = changeLineup { core.saveCustomChannel(draft) }
    fun deleteCustomChannel(channelID: String) = changeLineup { core.deleteCustomChannel(channelID) }

    /** Program start times change every schedule, so the channel on now is tuned again. */
    fun setScheduleGrid(grid: String) {
        scope.launch {
            val all = runCatching { core.setScheduleGrid(grid) }.getOrNull() ?: return@launch
            showChannels(all)
            tuner.channel.value?.let { tuner.tune(it, isAutomatic = true) }
        }
    }

    // MARK: Parental controls

    val parentalLock = ParentalLock(appContext)
    private val _parentalEnabled = MutableStateFlow(false)
    val parentalEnabled: StateFlow<Boolean> = _parentalEnabled.asStateFlow()

    /** Settings need the PIN: parental controls are on (or can't be read) and Settings aren't unlocked. */
    val needsParentalAuthorization: Boolean
        get() = parentalLock.isUnavailable || (_parentalEnabled.value && !parentalLock.isAuthorized.value)

    fun authorizeParental(pin: String) {
        if (parentalLock.authorize(pin)) updateParentalLock()
    }

    /** Settings closed: the next visit needs the PIN again. */
    fun endParentalAuthorization() {
        parentalLock.endAuthorization()
        updateParentalLock()
    }

    /**
     * Saves Settings › Parental Controls; [newPIN] sets the PIN when there isn't
     * one yet. Returns why it couldn't be saved, or `null`.
     */
    suspend fun saveParental(draft: ParentalDraft, newPIN: String?): String? {
        if (!parentalLock.hasPIN && draft.isEnabled) {
            if (newPIN == null || !parentalLock.setPIN(newPIN)) return parentalLock.message.value ?: "Create a PIN first."
        }
        val all = runCatching { core.saveParental(draft) }.getOrElse { return it.message ?: "Couldn't save parental controls." }
        _parentalEnabled.value = draft.isEnabled
        showChannels(all)
        updateParentalLock()
        // What's on may no longer be allowed: tune again under the new rules.
        (tuner.channel.value?.let { tuner.channelWithID(it.id) } ?: _channels.value.firstOrNull())?.let { tuner.tune(it, isAutomatic = true) }
        return null
    }

    private fun updateParentalLock() {
        scope.launch { runCatching { core.setParentalLocked(needsParentalAuthorization) } }
    }

    /** Settings › Servers › Add a server: the setup steps, while they're open. */
    private val _addingServer = MutableStateFlow<OnboardingModel?>(null)
    val addingServer: StateFlow<OnboardingModel?> = _addingServer.asStateFlow()

    fun beginAddingServer() {
        _addingServer.value = OnboardingModel(this, isAddingServer = true) { _addingServer.value = null }
    }

    /** Saves a server's library choice and reads its libraries again. */
    fun selectLibraries(serverID: String, selected: Set<String>, all: Boolean) {
        scope.launch {
            runCatching { core.selectLibraries(serverID, if (all) emptyList() else selected.toList()) }
            refresh(showsProgress = false)
        }
    }

    /** A server's quality or address changed: the core rebuilt the lineup, so show it and rejoin the channel. */
    fun serverSettingsChanged() {
        scope.launch {
            _servers.value = runCatching { core.servers() }.getOrDefault(_servers.value)
            reloadChannels()
            tuner.channel.value?.let { tuner.tune(it, isAutomatic = true) }
        }
    }

    /** Bumped after every lineup change, so open Settings pages reload. */
    private val _lineupRevision = MutableStateFlow(0)
    val lineupRevision: StateFlow<Int> = _lineupRevision.asStateFlow()

    /** Runs a lineup change in the core and shows its channels. */
    private fun changeLineup(change: suspend () -> List<ChannelInfo>) {
        scope.launch {
            val all = runCatching { change() }.getOrNull() ?: return@launch
            showChannels(all)
        }
    }

    /** Playing in a Picture in Picture window: only the picture shows. */
    private val _isPictureInPicture = MutableStateFlow(false)
    val isPictureInPicture: StateFlow<Boolean> = _isPictureInPicture.asStateFlow()

    fun setPictureInPicture(isOn: Boolean) {
        _isPictureInPicture.value = isOn
    }

    /** The app left the screen: release the stream and lock Settings again. */
    fun enteredBackground() {
        isInBackground = true
        updateHomeRow()
        endParentalAuthorization()
        tuner.suspend()
    }

    /** Back on screen: rejoin the channel live, catch up on reminders, and recheck servers. */
    fun becameActive() {
        if (!isInBackground) return
        isInBackground = false
        if (_phase.value != Phase.Ready) return
        reminders.reload()
        if (!sleepTimer.didExpire.value) tuner.resume()
        scope.launch { checkServers() }
    }

    /** Refreshes the home screen row (what's on, recent or favorite channels); the latest request wins. */
    fun updateHomeRow() {
        homeRowJob?.cancel()
        homeRowJob = scope.launch {
            val entries = runCatching { core.homeRow() }.getOrNull() ?: return@launch
            homeRow.update(entries)
        }
    }

    /** Tunes a channel from a link (`retroguide://channel?id=…`), now or once the lineup is ready. */
    fun openChannel(id: String) {
        preferences.edit().putString(Saved.LAST_CHANNEL, id).apply()
        tuner.channelWithID(id)?.let { tuner.tune(it) }
    }

    private var healthJob: Job? = null

    /** Rechecks servers every few minutes and whenever the network changes (the Apple app's health check). */
    private fun startHealthChecks() {
        if (healthJob != null) return
        healthJob = scope.launch {
            while (isActive) {
                delay(Refresh.HEALTH_CHECK_MS)
                if (!isInBackground) checkServers()
            }
        }
        network.start { scope.launch { checkServers() } }
    }

    /** Probes the servers; when one came back or dropped out the lineup was rebuilt, so show it. */
    private suspend fun checkServers() {
        if (_phase.value != Phase.Ready) return
        val result = runCatching { core.checkReachability(network.isVPNActive) }.getOrNull() ?: return
        if (!result.changed) return
        _servers.value = runCatching { core.servers() }.getOrDefault(_servers.value)
        _offline.value = _servers.value.filter { !it.isOnline }.map { it.name }
        reloadChannels()
    }

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
    fun start(development: CoreClient.DevelopmentServer? = null, developmentPro: Boolean = false) {
        scope.launch {
            try {
                if (developmentPro) setPro(true)
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
                        // Find each server's current address first: the network may have changed.
                        checkServers()
                        val cachedAt = started.oldestRefresh ?: 0.0
                        if (System.currentTimeMillis() / 1000.0 - cachedAt > Refresh.STALE_AFTER_SECONDS) refresh(showsProgress = false)
                    }
                    else -> refresh(showsProgress = true)
                }
                startHealthChecks()
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
            _isRefreshing.value = true
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
                _isRefreshing.value = false
            } catch (error: Exception) {
                _isRefreshing.value = false
                poll?.cancel()
                if (showsProgress) _phase.value = Phase.Failed(error.message ?: "Couldn't read your library.")
            }
        }
    }

    private suspend fun reloadChannels() {
        _parentalEnabled.value = runCatching { core.parentalStatus().isEnabled }.getOrDefault(_parentalEnabled.value)
        runCatching { core.setParentalLocked(needsParentalAuthorization) }
        _favoritesOnly.value = runCatching { core.viewing().favoritesOnly }.getOrDefault(false)
        showChannels(core.channels())
    }

    private fun showChannels(all: List<ChannelInfo>) {
        _lineupRevision.value += 1
        updateHomeRow()
        // A rebuilt lineup can move or remove reminded airings.
        reminders.reload()
        val visible = all.filter { !it.isHidden }
        _channels.value = visible
        tuner.setChannels(visible)
        updateSurfing()
    }

    private fun updateSurfing() {
        tuner.surfChannelIDs = if (_isPro.value && _favoritesOnly.value) browsingChannels().map { it.id }.toSet() else null
    }

    /** Powers the "TV" on to the last watched channel (or the first one). */
    private fun goOnAir() {
        if (_phase.value != Phase.Ready) _phase.value = Phase.Ready
        if (tuner.channel.value != null) return
        val last = tuner.channelWithID(preferences.getString(Saved.LAST_CHANNEL, null))
        (last ?: _channels.value.firstOrNull())?.let { tuner.tune(it, isAutomatic = true) }
    }
}
