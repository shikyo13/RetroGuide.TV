package com.adamhunt.retroguide.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.tv.material3.Text
import com.adamhunt.retroguide.ui.theme.LocalTheme
import com.adamhunt.retroguide.ui.theme.Tokens
import com.adamhunt.retroguide.ui.theme.Typography
import kotlinx.coroutines.delay

/** How long a page keeps trying to focus its first row while its rows load. */
private object PageFocus {
    const val ATTEMPTS = 40
    const val RETRY_MS = 50L
}

/**
 * One page of Settings: its title over a scrolling list of rows (the Apple
 * app's `SettingsPage`). Focus starts on the first row, or on the row the
 * viewer last chose here before going deeper ([navigator] remembers it).
 */
@Composable
fun SettingsPage(title: String, navigator: SettingsNavigator? = null, content: LazyListScope.() -> Unit) {
    val list = remember { FocusRequester() }
    val remembered = navigator?.remembered()
    val state = rememberLazyListState(initialFirstVisibleItemIndex = remembered?.firstVisible ?: 0)
    var hasFocus by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.md)) {
        Text(title, style = Typography.title, color = LocalTheme.current.textPrimary, maxLines = 1)
        LazyColumn(
            Modifier.focusRequester(list).onFocusChanged { hasFocus = it.hasFocus },
            state = state,
            verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.xs),
            content = content,
        )
    }
    // Rows may still be loading: keep trying until one takes focus.
    LaunchedEffect(title) {
        repeat(PageFocus.ATTEMPTS) {
            if (hasFocus) return@LaunchedEffect
            withFrameNanos {}
            runCatching { list.requestFocus() }
            delay(PageFocus.RETRY_MS)
        }
    }
    // Remember where this page was scrolled, for coming back to it.
    LaunchedEffect(state.firstVisibleItemIndex) { navigator?.remember(state.firstVisibleItemIndex) }
}
