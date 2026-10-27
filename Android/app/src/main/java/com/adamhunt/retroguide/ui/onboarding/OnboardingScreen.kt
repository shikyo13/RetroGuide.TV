package com.adamhunt.retroguide.ui.onboarding

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Text
import com.adamhunt.retroguide.ui.components.RetroTextField
import com.adamhunt.retroguide.ui.components.LocalShowsScanlines
import com.adamhunt.retroguide.ui.components.crtEffect
import com.adamhunt.retroguide.ui.components.BrandMark
import com.adamhunt.retroguide.ui.components.Panel
import com.adamhunt.retroguide.ui.components.RetroButton
import com.adamhunt.retroguide.ui.components.RetroRow
import com.adamhunt.retroguide.ui.components.qrCode
import com.adamhunt.retroguide.ui.theme.LocalTheme
import com.adamhunt.retroguide.ui.theme.Tokens
import com.adamhunt.retroguide.ui.theme.Typography
import com.adamhunt.retroguide.core.LibraryInfo

private object Layout {
    val columnWidth = 500.dp
    val qrSize = 150.dp
    val listHeight = 260.dp
}

@Composable
fun OnboardingScreen(model: OnboardingModel) {
    val theme = LocalTheme.current
    val step by model.step.collectAsState()
    // Back steps out of a sign-in; from the first step it leaves Add a server.
    BackHandler(enabled = model.isAddingServer || step != OnboardingModel.Step.Welcome) {
        if (step == OnboardingModel.Step.Welcome) model.cancel() else model.back()
    }
    Box(Modifier.fillMaxSize().background(theme.backgroundBrush).crtEffect(LocalShowsScanlines.current), contentAlignment = Alignment.Center) {
        Column(Modifier.width(Layout.columnWidth), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.lg)) {
            when (val current = step) {
                OnboardingModel.Step.Welcome -> Welcome(model)
                is OnboardingModel.Step.PlexLink -> PlexLink(current, model)
                is OnboardingModel.Step.PlexServers -> PlexServers(current, model)
                is OnboardingModel.Step.JellyfinAddress -> JellyfinAddress(current, model)
                is OnboardingModel.Step.JellyfinSignIn -> JellyfinSignIn(current, model)
                is OnboardingModel.Step.Connecting -> Message("Connecting to ${current.serverName}…")
                is OnboardingModel.Step.Libraries -> Libraries(current, model)
                is OnboardingModel.Step.Failed -> Failed(current, model)
            }
        }
    }
}

@Composable
private fun Welcome(model: OnboardingModel) {
    val theme = LocalTheme.current
    val first = remember { FocusRequester() }
    if (model.isAddingServer) {
        Text("Add a server", style = Typography.title, color = theme.textPrimary)
        Text("Its libraries join your channels. Servers added later come after the ones you have.",
            style = Typography.body, color = theme.textSecondary, textAlign = TextAlign.Center)
    } else {
        BrandMark(Typography.display)
        Text("Your library, on the air.", style = Typography.headline, color = theme.accentSecondary)
        Text(
            "RetroGuide.TV turns your Plex or Jellyfin library into live TV channels with a program guide. " +
                "Flip through channels, drop into whatever is on, and let the schedule do the choosing.",
            style = Typography.body, color = theme.textSecondary, textAlign = TextAlign.Center,
        )
    }
    Row(horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.md)) {
        RetroButton("Connect Plex", model::beginPlex, Modifier.focusRequester(first), isPrimary = true)
        RetroButton("Connect Jellyfin", model::beginJellyfin)
        if (model.isAddingServer) RetroButton("Cancel", model::cancel)
    }
    LaunchedEffect(Unit) { runCatching { first.requestFocus() } }
}

@Composable
private fun PlexLink(step: OnboardingModel.Step.PlexLink, model: OnboardingModel) {
    val theme = LocalTheme.current
    val back = remember { FocusRequester() }
    Text("Link your Plex account", style = Typography.title, color = theme.textPrimary)
    val code = step.code
    if (code == null) {
        Text("Getting a code…", style = Typography.body, color = theme.textSecondary)
    } else {
        Panel {
            Row(horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.xl), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.sm)) {
                    Text("On your phone or computer, go to", style = Typography.body, color = theme.textSecondary)
                    Text("plex.tv/link", style = Typography.headline, color = theme.accentSecondary)
                    Text("and enter this code:", style = Typography.body, color = theme.textSecondary)
                    Text(code.code, style = Typography.linkCode, color = theme.accent)
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Image(
                        qrCode(code.url), contentDescription = "Scan to open Plex link",
                        modifier = Modifier.size(Layout.qrSize).background(Color.White, RoundedCornerShape(Tokens.Radius.small)).padding(Tokens.Spacing.xs),
                        filterQuality = FilterQuality.None,
                    )
                    Text("Scan to open Plex link", style = Typography.caption, color = theme.textSecondary)
                }
            }
        }
        Text("Waiting for approval…", style = Typography.callout, color = theme.textSecondary)
    }
    RetroButton("Back", model::back, Modifier.focusRequester(back))
    LaunchedEffect(Unit) { runCatching { back.requestFocus() } }
}

@Composable
private fun PlexServers(step: OnboardingModel.Step.PlexServers, model: OnboardingModel) {
    val theme = LocalTheme.current
    val first = remember { FocusRequester() }
    Text("Choose a server", style = Typography.title, color = theme.textPrimary)
    LazyColumn(Modifier.heightIn(max = Layout.listHeight).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.xs)) {
        items(step.servers, key = { it.id }) { server ->
            RetroRow(
                server.name, onClick = { model.choosePlexServer(server) },
                modifier = if (server == step.servers.first()) Modifier.focusRequester(first) else Modifier,
                detail = if (server.isOwned) null else "Shared with you",
            )
        }
    }
    RetroButton("Back", model::back)
    LaunchedEffect(step) { runCatching { first.requestFocus() } }
}

@Composable
private fun JellyfinAddress(step: OnboardingModel.Step.JellyfinAddress, model: OnboardingModel) {
    val theme = LocalTheme.current
    var address by remember { mutableStateOf("") }
    val field = remember { FocusRequester() }
    Text("Enter your server's address", style = Typography.title, color = theme.textPrimary)
    Text(
        "Enter an HTTPS address with a trusted certificate, like https://jellyfin.example.com. " +
            "For a custom HTTPS port, include it in the address. HTTP connections are not supported.",
        style = Typography.callout, color = theme.textSecondary, textAlign = TextAlign.Center,
    )
    RetroTextField(address, { address = it }, "Server address", Modifier.focusRequester(field), KeyboardType.Uri) { model.findJellyfin(address) }
    step.message?.let { Text(it, style = Typography.callout, color = theme.accent, textAlign = TextAlign.Center) }
    Row(horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.md)) {
        RetroButton("Connect", { model.findJellyfin(address) }, isPrimary = true, enabled = address.isNotBlank())
        RetroButton("Back", model::back)
    }
    LaunchedEffect(Unit) { runCatching { field.requestFocus() } }
}

@Composable
private fun JellyfinSignIn(step: OnboardingModel.Step.JellyfinSignIn, model: OnboardingModel) {
    val theme = LocalTheme.current
    val first = remember { FocusRequester() }
    Text("Sign in to ${step.server.name}", style = Typography.title, color = theme.textPrimary)
    if (step.usesPassword) {
        var username by remember { mutableStateOf("") }
        var password by remember { mutableStateOf("") }
        RetroTextField(username, { username = it }, "Username", Modifier.focusRequester(first), KeyboardType.Text) {}
        RetroTextField(password, { password = it }, "Password", Modifier, KeyboardType.Password, isSecret = true) {
            model.signIn(step.server, username, password)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.md)) {
            RetroButton(if (step.isSigningIn) "Signing In…" else "Sign In", { model.signIn(step.server, username, password) },
                isPrimary = true, enabled = username.isNotBlank() && !step.isSigningIn)
            if (step.server.hasQuickConnect) RetroButton("Use Quick Connect", { model.startQuickConnect(step.server) })
        }
    } else {
        Text("In Jellyfin on your phone or computer, open your profile, choose Quick Connect and enter this code:",
            style = Typography.body, color = theme.textSecondary, textAlign = TextAlign.Center)
        Text(step.quickConnectCode ?: "…", style = Typography.linkCode, color = theme.accent)
        Text("Waiting for approval…", style = Typography.callout, color = theme.textSecondary)
        RetroButton("Use Password Instead", { model.usePassword(step.server) }, Modifier.focusRequester(first))
    }
    step.message?.let { Text(it, style = Typography.callout, color = theme.accent, textAlign = TextAlign.Center) }
    RetroButton("Cancel", model::back)
    LaunchedEffect(step.usesPassword) { runCatching { first.requestFocus() } }
}

@Composable
private fun Libraries(step: OnboardingModel.Step.Libraries, model: OnboardingModel) {
    val theme = LocalTheme.current
    var selected by remember(step) { mutableStateOf(step.libraries.filter(LibraryInfo::isSelected).map(LibraryInfo::id).toSet()) }
    val build = remember { FocusRequester() }
    Text("Which libraries should be on TV?", style = Typography.title, color = theme.textPrimary)
    LazyColumn(Modifier.heightIn(max = Layout.listHeight).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.xs)) {
        items(step.libraries, key = { it.id }) { library ->
            val isOn = library.id in selected
            RetroRow(
                library.title,
                onClick = { selected = if (isOn) selected - library.id else selected + library.id },
                detail = library.kind.replaceFirstChar(Char::uppercase),
                trailing = if (isOn) "✓" else "",
            )
        }
    }
    RetroButton("Build My Channels", { model.buildChannels(step, selected) }, Modifier.focusRequester(build), isPrimary = true, enabled = selected.isNotEmpty())
    LaunchedEffect(step) { runCatching { build.requestFocus() } }
}

@Composable
private fun Failed(step: OnboardingModel.Step.Failed, model: OnboardingModel) {
    val theme = LocalTheme.current
    val back = remember { FocusRequester() }
    Text("Something went wrong", style = Typography.title, color = theme.textPrimary)
    Text(step.message, style = Typography.body, color = theme.textSecondary, textAlign = TextAlign.Center)
    RetroButton("Back", model::back, Modifier.focusRequester(back))
    LaunchedEffect(Unit) { runCatching { back.requestFocus() } }
}

@Composable
private fun Message(text: String) {
    Text(text, style = Typography.headline, color = LocalTheme.current.textSecondary)
}

