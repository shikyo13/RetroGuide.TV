package com.adamhunt.retroguide.ui.onboarding

import com.adamhunt.retroguide.AppModel
import com.adamhunt.retroguide.core.CoreException
import com.adamhunt.retroguide.core.JellyfinServerOption
import com.adamhunt.retroguide.core.LibraryInfo
import com.adamhunt.retroguide.core.LinkCode
import com.adamhunt.retroguide.core.PlexServerOption
import com.adamhunt.retroguide.core.ServersChange
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

/** First-run setup: Plex or Jellyfin, sign in, pick a server and its libraries (the Apple app's `OnboardingModel`). */
class OnboardingModel(
    private val app: AppModel,
    /** Settings › Add a server rather than first-run setup: a saved Plex account skips the link code. */
    val isAddingServer: Boolean = false,
    private val onFinished: () -> Unit = {},
) {
    sealed interface Step {
        data object Welcome : Step
        data class PlexLink(val code: LinkCode?) : Step
        data class PlexServers(val servers: List<PlexServerOption>) : Step
        data class JellyfinAddress(val message: String?) : Step
        data class JellyfinSignIn(
            val server: JellyfinServerOption,
            val quickConnectCode: String?,
            val usesPassword: Boolean,
            val message: String?,
            val isSigningIn: Boolean = false,
        ) : Step
        data class Connecting(val serverName: String) : Step
        data class Libraries(
            val serverID: String,
            val serverName: String,
            val libraries: List<LibraryInfo>,
            val change: ServersChange,
        ) : Step
        data class Failed(val message: String) : Step
    }

    private object Timing {
        /** How often a pending Plex link or Quick Connect approval is checked. */
        const val POLL_MS = 3_000L
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val core = app.core
    private val _step = MutableStateFlow<Step>(Step.Welcome)
    val step: StateFlow<Step> = _step.asStateFlow()
    private var poll: Job? = null

    fun back() {
        poll?.cancel()
        _step.value = Step.Welcome
    }

    /** Leaves Add a server without adding one. */
    fun cancel() {
        poll?.cancel()
        onFinished()
    }

    // MARK: Plex

    fun beginPlex() {
        poll?.cancel()
        _step.value = Step.PlexLink(null)
        poll = scope.launch {
            // With a Plex account already linked, go straight to its servers.
            if (isAddingServer) {
                runCatching { core.plexServers() }.getOrNull()?.let { servers ->
                    _step.value = if (servers.isEmpty()) {
                        Step.Failed("There are no additional Plex servers available on this account.")
                    } else {
                        Step.PlexServers(servers)
                    }
                    return@launch
                }
            }
            val code = attempt { core.plexLinkCode() } ?: return@launch
            _step.value = Step.PlexLink(code)
            while (isActive) {
                delay(Timing.POLL_MS)
                val status = attempt { core.checkPlexLink(code.id) } ?: return@launch
                if (status.isLinked) break
            }
            val servers = attempt { core.plexServers() } ?: return@launch
            _step.value = if (servers.isEmpty()) {
                Step.Failed("There are no additional Plex servers available on this account.")
            } else {
                Step.PlexServers(servers)
            }
        }
    }

    fun choosePlexServer(server: PlexServerOption) {
        _step.value = Step.Connecting(server.name)
        scope.launch {
            val change = attempt { core.addPlexServers(listOf(server.id)) } ?: return@launch
            showLibraries(change, server.id, server.name)
        }
    }

    // MARK: Jellyfin

    fun beginJellyfin() {
        poll?.cancel()
        _step.value = Step.JellyfinAddress(null)
    }

    fun findJellyfin(address: String) {
        if (address.isBlank()) return
        _step.value = Step.Connecting(address)
        scope.launch {
            val server = try {
                core.findJellyfin(address.trim())
            } catch (error: CoreException) {
                _step.value = Step.JellyfinAddress(error.message)
                return@launch
            }
            if (server.hasQuickConnect) startQuickConnect(server) else usePassword(server)
        }
    }

    fun usePassword(server: JellyfinServerOption) {
        poll?.cancel()
        _step.value = Step.JellyfinSignIn(server, quickConnectCode = null, usesPassword = true, message = null)
    }

    fun startQuickConnect(server: JellyfinServerOption) {
        poll?.cancel()
        _step.value = Step.JellyfinSignIn(server, quickConnectCode = null, usesPassword = false, message = null)
        poll = scope.launch {
            val code = try {
                core.startQuickConnect()
            } catch (error: CoreException) {
                _step.value = Step.JellyfinSignIn(server, null, usesPassword = true,
                    message = "Quick Connect isn't working right now (${error.message}). Sign in with your password instead.")
                return@launch
            }
            _step.value = Step.JellyfinSignIn(server, code.code, usesPassword = false, message = null)
            while (isActive) {
                delay(Timing.POLL_MS)
                val status = attempt { core.checkQuickConnect() } ?: return@launch
                val change = status.change
                if (status.isApproved && change != null) {
                    showLibraries(change, server.id, server.name)
                    return@launch
                }
            }
        }
    }

    fun signIn(server: JellyfinServerOption, username: String, password: String) {
        _step.value = Step.JellyfinSignIn(server, null, usesPassword = true, message = null, isSigningIn = true)
        scope.launch {
            val change = try {
                core.signInJellyfin(username, password)
            } catch (error: CoreException) {
                _step.value = Step.JellyfinSignIn(server, null, usesPassword = true, message = "That username and password didn't work.")
                return@launch
            }
            showLibraries(change, server.id, server.name)
        }
    }

    // MARK: Libraries

    private suspend fun showLibraries(change: ServersChange, serverID: String, serverName: String) {
        val libraries = attempt { core.libraries(serverID) } ?: return
        _step.value = Step.Libraries(serverID, serverName, libraries, change)
    }

    /** Saves the chosen libraries (all of them selects ones added later too) and builds the channels. */
    fun buildChannels(step: Step.Libraries, selectedIDs: Set<String>) {
        scope.launch {
            val all = selectedIDs.size == step.libraries.size
            attempt { core.selectLibraries(step.serverID, if (all) emptyList() else selectedIDs.toList()) } ?: return@launch
            app.serversChanged(step.change)
            onFinished()
        }
    }

    private suspend fun <T> attempt(work: suspend () -> T): T? = try {
        work()
    } catch (error: Exception) {
        _step.value = Step.Failed(error.message ?: "Something went wrong")
        null
    }
}
