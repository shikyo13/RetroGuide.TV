package com.adamhunt.retroguide.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Text
import com.adamhunt.retroguide.AppModel
import com.adamhunt.retroguide.Phase
import com.adamhunt.retroguide.ui.components.BrandMark
import com.adamhunt.retroguide.ui.components.Panel
import com.adamhunt.retroguide.ui.components.ProgressTrack
import com.adamhunt.retroguide.ui.components.RetroButton
import com.adamhunt.retroguide.ui.onboarding.OnboardingModel
import com.adamhunt.retroguide.ui.onboarding.OnboardingScreen
import com.adamhunt.retroguide.ui.theme.LocalTheme
import com.adamhunt.retroguide.ui.theme.Theme
import com.adamhunt.retroguide.ui.theme.Tokens
import com.adamhunt.retroguide.ui.theme.Typography
import com.adamhunt.retroguide.ui.watch.WatchScreen

/** Switches between the app's top-level phases (the Apple app's `RootView`). */
@Composable
fun RootScreen(app: AppModel) {
    val phase by app.phase.collectAsState()
    val themeID by app.themeID.collectAsState()
    CompositionLocalProvider(LocalTheme provides Theme.of(themeID)) {
        when (val current = phase) {
            Phase.Launching -> Splash()
            Phase.Onboarding -> OnboardingScreen(remember { OnboardingModel(app) })
            is Phase.Indexing -> Indexing(current)
            is Phase.Failed -> Failed(current.message, app::retry)
            Phase.Ready -> WatchScreen(app)
        }
    }
}

@Composable
private fun Splash() {
    Box(Modifier.fillMaxSize().background(LocalTheme.current.backgroundBrush), contentAlignment = Alignment.Center) {
        BrandMark(Typography.display)
    }
}

@Composable
private fun Indexing(phase: Phase.Indexing) {
    val theme = LocalTheme.current
    Box(Modifier.fillMaxSize().background(theme.backgroundBrush), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.xl)) {
            BrandMark(Typography.display)
            Panel(Modifier.width(420.dp)) {
                Text("Programming your channels", style = Typography.headline, color = theme.textPrimary,
                    modifier = Modifier.align(Alignment.CenterHorizontally))
                ProgressTrack(phase.progress.fraction.toFloat(), Modifier.fillMaxWidth(), Tokens.Spacing.xs)
                Text(phase.progress.message, style = Typography.callout, color = theme.textSecondary, maxLines = 1,
                    modifier = Modifier.align(Alignment.CenterHorizontally))
            }
        }
    }
}

@Composable
private fun Failed(message: String, onRetry: () -> Unit) {
    val theme = LocalTheme.current
    val retry = remember { FocusRequester() }
    Box(Modifier.fillMaxSize().background(theme.backgroundBrush), contentAlignment = Alignment.Center) {
        Column(Modifier.width(500.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.lg)) {
            Text("Something went wrong", style = Typography.title, color = theme.textPrimary)
            Text(message, style = Typography.body, color = theme.textSecondary, textAlign = TextAlign.Center)
            RetroButton("Try Again", onRetry, Modifier.focusRequester(retry), isPrimary = true)
        }
    }
    LaunchedEffect(Unit) { runCatching { retry.requestFocus() } }
}

