package com.adamhunt.retroguide.ui.search

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.Surface
import androidx.tv.material3.Text
import coil3.compose.AsyncImage
import com.adamhunt.retroguide.AppModel
import com.adamhunt.retroguide.core.SearchHit
import com.adamhunt.retroguide.ui.components.Note
import com.adamhunt.retroguide.ui.components.CornerPicture
import com.adamhunt.retroguide.ui.components.RetroTextField
import com.adamhunt.retroguide.ui.components.screenBackground
import com.adamhunt.retroguide.ui.theme.LocalTheme
import com.adamhunt.retroguide.ui.theme.Tokens
import com.adamhunt.retroguide.ui.theme.Typography
import com.adamhunt.retroguide.ui.watch.ScheduleFormatting
import com.adamhunt.retroguide.ui.watch.nowSeconds
import kotlinx.coroutines.delay

/** Sizes of Search (the Apple app's `SearchView`, halved for Android TV's dp grid). */
object SearchLayout {
    val margin = 40.dp
    val top = 24.dp
    val resultsWidth = 575.dp
    val posterWidth = 32.dp
    val posterHeight = 48.dp
}

private object SearchTiming {
    /** Brief pause after a keystroke before searching, so fast typing stays smooth. */
    const val DEBOUNCE_MS = 150L
    /** How often open results refresh, so "on now" stays true as programs end. */
    const val REFRESH_MS = 60_000L
}

/** Finds shows and movies on the channels, with results that update as you type. */
@Composable
fun SearchScreen(app: AppModel, screen: DpSize, onTune: (String) -> Unit, onClose: () -> Unit) {
    val theme = LocalTheme.current
    var query by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<SearchHit>>(emptyList()) }
    val field = remember { FocusRequester() }
    BackHandler(onBack = onClose)
    LaunchedEffect(query) {
        delay(SearchTiming.DEBOUNCE_MS)
        while (true) {
            results = if (query.isBlank()) emptyList() else runCatching { app.core.search(query) }.getOrDefault(emptyList())
            delay(SearchTiming.REFRESH_MS)
        }
    }
    LaunchedEffect(Unit) { runCatching { field.requestFocus() } }
    Box(Modifier.fillMaxSize().screenBackground(theme, CornerPicture.window(screen))) {
        Column(
            Modifier.padding(start = SearchLayout.margin, top = SearchLayout.top).width(SearchLayout.resultsWidth),
            verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.sm),
        ) {
            Text("Search", style = Typography.title, color = theme.textPrimary)
            RetroTextField(
                query, { query = it }, "Shows and movies", Modifier.focusRequester(field),
                // Search opens ready to type.
                KeyboardType.Text, imeAction = ImeAction.Search, startsEditing = true,
            ) {}
            LazyColumn(verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.xs)) {
                items(results, key = { it.id }) { hit ->
                    ResultRow(hit) { hit.channelID?.let(onTune) }
                }
                if (results.isEmpty()) {
                    item {
                        Note(if (query.isBlank()) "Search every show and movie on your channels." else "Nothing on your channels matches “$query”.")
                    }
                }
            }
        }
    }
}

/** A result: poster, title, and when and where it airs next. */
@Composable
private fun ResultRow(hit: SearchHit, onClick: () -> Unit) {
    val theme = LocalTheme.current
    Surface(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth().defaultMinSize(minHeight = Tokens.Control.minimumHeight),
        shape = ClickableSurfaceDefaults.shape(RoundedCornerShape(Tokens.Radius.medium)),
        scale = ClickableSurfaceDefaults.scale(focusedScale = Tokens.Scale.ROW_FOCUSED),
        colors = ClickableSurfaceDefaults.colors(
            containerColor = theme.surface,
            contentColor = theme.textPrimary,
            focusedContainerColor = theme.focusFill,
            focusedContentColor = theme.textOnFocus,
        ),
    ) {
        Row(
            Modifier.padding(Tokens.Spacing.sm),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.md),
        ) {
            AsyncImage(
                model = hit.poster, contentDescription = null, contentScale = ContentScale.Crop,
                modifier = Modifier.size(SearchLayout.posterWidth, SearchLayout.posterHeight)
                    .clip(RoundedCornerShape(Tokens.Radius.small)).background(theme.surfaceRaised),
            )
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.xxs)) {
                Text(hit.title, style = Typography.bodyEmphasis, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(airingText(hit), style = Typography.caption, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            if (hit.channelNumber != null && hit.callSign != null) {
                Text("${hit.channelNumber} ${hit.callSign}", style = Typography.callSign)
            }
        }
    }
}

private fun airingText(hit: SearchHit): String {
    val channel = hit.channelName ?: return hit.kind
    val airing = hit.airing ?: return "On $channel · not scheduled in the next two days"
    val now = nowSeconds()
    return if (airing.start <= now && now < airing.end) {
        "On now · $channel · ${ScheduleFormatting.remaining(airing, now)}"
    } else {
        "Next: ${ScheduleFormatting.dayAndTime(airing.start)} · $channel"
    }
}
