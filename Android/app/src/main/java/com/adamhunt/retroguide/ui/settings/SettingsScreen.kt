package com.adamhunt.retroguide.ui.settings

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Text
import com.adamhunt.retroguide.AppModel
import com.adamhunt.retroguide.BuildConfig
import com.adamhunt.retroguide.core.ServerInfo
import com.adamhunt.retroguide.ui.components.RetroRow
import com.adamhunt.retroguide.ui.theme.LocalTheme
import com.adamhunt.retroguide.ui.theme.ThemePalettes
import com.adamhunt.retroguide.ui.theme.Tokens
import com.adamhunt.retroguide.ui.theme.Typography

private sealed interface Page {
    data object Main : Page
    data object Themes : Page
    data class Server(val server: ServerInfo) : Page
}

/** Settings (the Apple app's `SettingsView`): theme, servers, library and account. */
@Composable
fun SettingsScreen(app: AppModel, onClose: () -> Unit) {
    val theme = LocalTheme.current
    var page by remember { mutableStateOf<Page>(Page.Main) }
    BackHandler { if (page == Page.Main) onClose() else page = Page.Main }
    Box(Modifier.fillMaxSize().background(theme.backgroundBrush).padding(horizontal = 40.dp, vertical = 24.dp)) {
        Column(Modifier.width(560.dp), verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.md)) {
            when (val current = page) {
                Page.Main -> {
                    Text("Settings", style = Typography.title, color = theme.textPrimary)
                    MainPage(app, onPage = { page = it })
                }
                Page.Themes -> {
                    Text("Theme", style = Typography.title, color = theme.textPrimary)
                    ThemesPage(app) { page = Page.Main }
                }
                is Page.Server -> {
                    Text(current.server.name, style = Typography.title, color = theme.textPrimary)
                    ServerPage(app, current.server) { page = Page.Main }
                }
            }
        }
    }
}

@Composable
private fun MainPage(app: AppModel, onPage: (Page) -> Unit) {
    val theme = LocalTheme.current
    val servers by app.servers.collectAsState()
    val themeID by app.themeID.collectAsState()
    val first = remember { FocusRequester() }
    LazyColumn(verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.xs)) {
        item { Section("Picture") }
        item {
            RetroRow("Theme", { onPage(Page.Themes) }, Modifier.focusRequester(first),
                trailing = ThemePalettes.first { it.id == themeID }.name)
        }
        item { Section("Library") }
        items(servers, key = { it.id }) { server ->
            RetroRow(server.name, { onPage(Page.Server(server)) },
                detail = "${server.kind.replaceFirstChar(Char::uppercase)} · ${server.address}",
                trailing = if (server.isOnline) "Online" else "Offline")
        }
        item { RetroRow("Add another server", {}, trailing = if (app.isPro.value) "" else "Pro 🔒") }
        item { RetroRow("Refresh library", { app.refresh(showsProgress = false) }) }
        item { Section("Account") }
        item { RetroRow("Sign out", app::signOut, detail = "Removes every server and channel from this device") }
        item {
            Text("RetroGuide.TV ${BuildConfig.VERSION_NAME} · Open source under the MIT License", style = Typography.caption,
                color = theme.textSecondary, modifier = Modifier.padding(top = Tokens.Spacing.md))
        }
    }
    LaunchedEffect(Unit) { runCatching { first.requestFocus() } }
}

@Composable
private fun ThemesPage(app: AppModel, onDone: () -> Unit) {
    val themeID by app.themeID.collectAsState()
    val current = remember { FocusRequester() }
    LazyColumn(verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.xs)) {
        items(ThemePalettes, key = { it.id }) { palette ->
            val locked = !palette.id.isIncludedFree && !app.isPro.value
            RetroRow(
                palette.name,
                onClick = { if (!locked) { app.setTheme(palette.id); onDone() } },
                modifier = if (palette.id == themeID) Modifier.focusRequester(current) else Modifier,
                trailing = when {
                    palette.id == themeID -> "✓"
                    locked -> "Pro 🔒"
                    else -> ""
                },
            )
        }
    }
    LaunchedEffect(Unit) { runCatching { current.requestFocus() } }
}

@Composable
private fun ServerPage(app: AppModel, server: ServerInfo, onDone: () -> Unit) {
    val theme = LocalTheme.current
    val first = remember { FocusRequester() }
    Text("${server.kind.replaceFirstChar(Char::uppercase)} · ${server.address} · ${if (server.isOnline) "Online" else "Offline"}",
        style = Typography.body, color = theme.textSecondary)
    RetroRow("Remove server", { app.removeServer(server.id); onDone() }, Modifier.focusRequester(first),
        detail = "Its programs will leave every channel.")
    LaunchedEffect(Unit) { runCatching { first.requestFocus() } }
}

@Composable
private fun Section(title: String) {
    Text(title.uppercase(), style = Typography.captionEmphasis, color = LocalTheme.current.accentSecondary,
        modifier = Modifier.padding(top = Tokens.Spacing.md, start = Tokens.Spacing.xs))
}
