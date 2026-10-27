package com.adamhunt.retroguide.ui.settings

import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import com.adamhunt.retroguide.AppModel
import com.adamhunt.retroguide.core.LibraryInfo
import com.adamhunt.retroguide.core.ServerDetail
import com.adamhunt.retroguide.ui.components.CheckmarkRow
import com.adamhunt.retroguide.ui.components.Note
import com.adamhunt.retroguide.ui.components.ProLockedRow
import com.adamhunt.retroguide.ui.components.RetroButton
import com.adamhunt.retroguide.ui.components.RetroRow
import com.adamhunt.retroguide.ui.components.RetroTextField
import com.adamhunt.retroguide.ui.components.SectionHeader
import kotlinx.coroutines.launch

/** Kit `ServerKind` and `ConnectionPreference` raw values the pages branch on. */
private object ServerValues {
    const val PLEX = "plex"
    const val CUSTOM = "custom"
}

/** Connected servers in priority order, plus "Add a server" (the Apple app's `ServersView`). */
@Composable
fun ServersPage(app: AppModel, navigator: SettingsNavigator) {
    val servers by app.servers.collectAsState()
    val settings = rememberLineupSettings(app)
    SettingsPage("Servers", navigator) {
        item {
            Note("Channels combine content from your selected libraries. For matching copies, servers higher in this list are preferred. Availability, parental restrictions and playable versions can affect which copy is used.")
        }
        item { SectionHeader("Connected") }
        items(servers, key = { it.id }) { server ->
            RetroRow(server.name, { navigator.open(SettingsRoute.Server(server.id)) },
                detail = "${server.kind.replaceFirstChar(Char::uppercase)} · ${server.address}",
                trailing = if (server.isOnline) "Online" else "Offline")
        }
        item {
            if (settings?.canAddServer != false) {
                RetroRow("Add a server", { app.beginAddingServer() })
            } else {
                ProLockedRow("Add another server", { navigator.open(SettingsRoute.Pro) })
            }
        }
    }
}

/** One server: playback, connection, libraries and removal (the Apple app's `ServerDetailView`). */
@Composable
fun ServerPage(app: AppModel, navigator: SettingsNavigator, serverID: String) {
    val scope = rememberCoroutineScope()
    var detail by remember { mutableStateOf<ServerDetail?>(null) }
    var libraries by remember { mutableStateOf<List<LibraryInfo>?>(null) }
    var selected by remember { mutableStateOf<Set<String>>(emptySet()) }
    var addressText by remember { mutableStateOf("") }
    var message by remember { mutableStateOf<String?>(null) }
    var isApplying by remember { mutableStateOf(false) }
    var isConfirmingRemoval by remember { mutableStateOf(false) }
    LaunchedEffect(serverID) {
        detail = runCatching { app.core.serverDetail(serverID) }.getOrNull()
        addressText = detail?.let { it.customAddress ?: if (it.kind == ServerValues.PLEX) "" else it.address }.orEmpty()
        libraries = runCatching { app.core.libraries(serverID) }.getOrNull()
        selected = libraries.orEmpty().filter { it.isSelected }.map { it.id }.toSet()
    }
    val server = detail ?: run {
        SettingsPage("Server") {}
        return
    }

    fun applyConnection(preference: String, address: String?) {
        isApplying = true
        message = null
        scope.launch {
            runCatching { app.core.setConnection(serverID, preference, address) }
                .onSuccess { result ->
                    detail = result.server
                    message = result.message
                    app.serverSettingsChanged()
                }
                .onFailure { message = it.message }
            isApplying = false
        }
    }

    SettingsPage(server.name, navigator) {
        item { Note(if (isApplying) "Connecting…" else server.status) }

        item { SectionHeader("Video quality") }
        item {
            Note("Choose which existing copy to prefer on ${server.name}, such as 4K or 1080p. This does not set a streaming bitrate.")
        }
        items(server.qualities, key = { "quality-${it.id}" }) { quality ->
            CheckmarkRow(quality.title, server.quality == quality.id, {
                scope.launch {
                    runCatching { app.core.setPlayback(serverID, quality = quality.id) }.getOrNull()?.let { detail = it }
                    app.serverSettingsChanged()
                }
            }, detail = quality.detail)
        }
        item {
            RetroRow("Extra buffering", {
                scope.launch {
                    runCatching { app.core.setPlayback(serverID, extraBuffering = !server.extraBuffering) }.getOrNull()?.let { detail = it }
                    app.serverSettingsChanged()
                }
            }, trailing = if (server.extraBuffering) "On" else "Off")
        }
        item { Note("Extra buffering reads further ahead so playback rides out slow or uneven internet. Turn it on for servers outside your home.") }

        if (server.kind == ServerValues.PLEX) {
            item { SectionHeader("Connection") }
            items(server.connections, key = { "connection-${it.id}" }) { connection ->
                CheckmarkRow(connection.title, server.connection == connection.id, { applyConnection(connection.id, null) }, detail = connection.detail)
            }
            if (server.connection == ServerValues.CUSTOM) {
                item { RetroTextField(addressText, { addressText = it }, "100.x.x.x or hostname", Modifier, KeyboardType.Uri) { applyConnection(ServerValues.CUSTOM, addressText) } }
                item { RetroButton("Use this address", { applyConnection(ServerValues.CUSTOM, addressText) }, enabled = !isApplying && addressText.isNotBlank()) }
                item {
                    Note("Enter an HTTPS address with a trusted certificate. Port 32400 is used unless you add one. A Tailscale IP uses the server's secure plex.direct hostname when available. HTTP connections are not supported.")
                }
            }
        } else {
            item { SectionHeader("Server address") }
            item { RetroTextField(addressText, { addressText = it }, "https://jellyfin.example.com", Modifier, KeyboardType.Uri) {} }
            item {
                RetroButton("Use this address", {
                    isApplying = true
                    scope.launch {
                        runCatching { app.core.setJellyfinAddress(serverID, addressText.trim()) }
                            .onSuccess { result ->
                                detail = result.server
                                message = result.message
                                app.serverSettingsChanged()
                            }
                        isApplying = false
                    }
                }, enabled = !isApplying && addressText.isNotBlank())
            }
        }
        message?.let { item { Note(it, emphasized = true) } }

        item { SectionHeader("Libraries") }
        val available = libraries
        if (available == null) {
            item { Note("Loading libraries…") }
        } else {
            items(available, key = { "library-${it.id}" }) { library ->
                CheckmarkRow(library.title, library.id in selected, {
                    selected = if (library.id in selected) selected - library.id else selected + library.id
                }, detail = library.kind.replaceFirstChar(Char::uppercase))
            }
            item {
                val original = available.filter { it.isSelected }.map { it.id }.toSet()
                RetroButton("Save and Rebuild Channels", {
                    app.selectLibraries(serverID, selected, all = selected.size == available.size)
                    navigator.back()
                }, enabled = selected.isNotEmpty() && selected != original)
            }
        }

        item { SectionHeader("Server") }
        if (isConfirmingRemoval) {
            item { Note("Remove ${server.name}? Its programs will leave every channel.") }
            item {
                RetroRow("Remove", {
                    app.removeServer(serverID)
                    navigator.back()
                })
            }
            item { RetroRow("Cancel", { isConfirmingRemoval = false }) }
        } else {
            item { RetroRow("Remove server", { isConfirmingRemoval = true }) }
        }
    }
}
