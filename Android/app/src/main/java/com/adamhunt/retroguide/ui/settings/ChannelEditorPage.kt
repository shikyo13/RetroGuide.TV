package com.adamhunt.retroguide.ui.settings

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.tv.material3.Text
import com.adamhunt.retroguide.AppModel
import com.adamhunt.retroguide.core.ChannelDraft
import com.adamhunt.retroguide.core.ChannelFacets
import com.adamhunt.retroguide.core.ChannelPreview
import com.adamhunt.retroguide.core.FacetOption
import com.adamhunt.retroguide.core.ParentalDraft
import com.adamhunt.retroguide.ui.components.CheckmarkRow
import com.adamhunt.retroguide.ui.components.Note
import com.adamhunt.retroguide.ui.components.ProLockedRow
import com.adamhunt.retroguide.ui.components.RetroButton
import com.adamhunt.retroguide.ui.components.RetroRow
import com.adamhunt.retroguide.ui.components.RetroTextField
import com.adamhunt.retroguide.ui.components.SectionHeader
import com.adamhunt.retroguide.ui.theme.LocalTheme
import com.adamhunt.retroguide.ui.theme.Typography

/** A filter the editor's rule is built from, and how to read and change it in a draft. */
private enum class Filter(val title: String) {
    GENRES("Genres"), SHOWS("Shows"), NETWORKS("Networks"), COLLECTIONS("Collections"),
    DECADES("Decades"), AUDIENCE("Audience"), LIBRARIES("Libraries");

    fun options(facets: ChannelFacets): List<FacetOption> = when (this) {
        GENRES -> facets.categories
        SHOWS -> facets.series
        NETWORKS -> facets.networks
        COLLECTIONS -> facets.collections
        DECADES -> facets.decades
        AUDIENCE -> facets.audiences
        LIBRARIES -> facets.libraries
    }

    fun selection(draft: ChannelDraft): Set<String> = when (this) {
        GENRES -> draft.categories.toSet()
        SHOWS -> draft.seriesIDs.toSet()
        NETWORKS -> draft.networks.toSet()
        COLLECTIONS -> draft.collections.toSet()
        DECADES -> draft.decades.map(Int::toString).toSet()
        AUDIENCE -> draft.audiences.toSet()
        LIBRARIES -> draft.libraryIDs.toSet()
    }

    fun with(draft: ChannelDraft, selection: Set<String>): ChannelDraft = when (this) {
        GENRES -> draft.copy(categories = selection.sorted())
        SHOWS -> draft.copy(seriesIDs = selection.sorted())
        NETWORKS -> draft.copy(networks = selection.sorted())
        COLLECTIONS -> draft.copy(collections = selection.sorted())
        DECADES -> draft.copy(decades = selection.mapNotNull(String::toIntOrNull).sorted())
        AUDIENCE -> draft.copy(audiences = selection.sorted())
        LIBRARIES -> draft.copy(libraryIDs = selection.sorted())
    }
}

/** Editing a channel of the parental custom lineup (saved with the policy, not the lineup). */
class ParentalChannelEditing(
    val policy: ParentalDraft,
    val onSave: (ChannelDraft) -> Unit,
    val onDelete: (() -> Unit)?,
)

/** Lists longer than this get a search field. */
private const val SEARCH_THRESHOLD = 15

/**
 * Builds or edits a custom channel from any combination of filters, with a
 * live preview (the Apple app's `ChannelEditorView` and `FacetPickerView`).
 */
@Composable
fun ChannelEditorPage(
    app: AppModel,
    navigator: SettingsNavigator,
    initial: ChannelDraft,
    /** Parental custom lineup: previews from what the policy allows, and saves into it. */
    parental: ParentalChannelEditing? = null,
) {
    val theme = LocalTheme.current
    val isPro by app.isPro.collectAsState()
    var draft by remember { mutableStateOf(initial) }
    var facets by remember { mutableStateOf<ChannelFacets?>(null) }
    var preview by remember { mutableStateOf<ChannelPreview?>(null) }
    var picking by remember { mutableStateOf<Filter?>(null) }
    val isNew = initial.id == null
    val settings = rememberLineupSettings(app)
    LaunchedEffect(Unit) { facets = runCatching { app.core.channelFacets() }.getOrNull() }
    LaunchedEffect(draft.copy(name = "")) {
        preview = runCatching {
            if (parental != null) app.core.previewParentalChannel(draft, parental.policy) else app.core.previewChannel(draft)
        }.getOrNull()
    }

    picking?.let { filter ->
        BackHandler { picking = null }
        FacetPickerPage(filter.title, facets?.let(filter::options).orEmpty(), filter.selection(draft)) { draft = filter.with(draft, it) }
        return
    }
    val canSave = draft.name.isNotBlank() && ((preview?.programCount ?: 0) > 0 || !isNew)
    SettingsPage(if (isNew) "New Channel" else "Edit Channel") {
        item { SectionHeader("Name") }
        item { RetroTextField(draft.name, { draft = draft.copy(name = it) }, "Channel name", Modifier, KeyboardType.Text) {} }
        item { SectionHeader("What's on") }
        items(facets?.kinds.orEmpty(), key = { "kind-${it.id}" }) { kind ->
            CheckmarkRow(kind.title, kind.id in draft.kinds, {
                draft = draft.copy(kinds = if (kind.id in draft.kinds) draft.kinds - kind.id else draft.kinds + kind.id)
            })
        }
        items(Filter.entries, key = { "filter-${it.name}" }) { filter ->
            RetroRow(filter.title, { picking = filter }, trailing = summary(filter.selection(draft), facets?.let(filter::options).orEmpty()))
        }
        item { SectionHeader("Schedule order") }
        if (isPro) {
            items(settings?.orderings.orEmpty(), key = { "order-${it.id}" }) { ordering ->
                CheckmarkRow(ordering.title, draft.ordering == ordering.id, { draft = draft.copy(ordering = ordering.id) }, detail = ordering.detail)
            }
        } else {
            item { ProLockedRow("Change schedule order", { navigator.open(SettingsRoute.Pro) }) }
        }
        item {
            val current = preview
            Text(current?.summary ?: "", style = Typography.headline,
                color = if ((current?.programCount ?: 0) > 0) theme.accent else theme.textSecondary)
        }
        preview?.shows?.takeIf { it.isNotEmpty() }?.let { shows -> item { Note(shows.joinToString(" · ")) } }
        item {
            RetroButton(if (isNew) "Create Channel" else "Save Changes", {
                if (parental != null) parental.onSave(draft) else {
                    app.saveCustomChannel(draft)
                    navigator.back()
                }
            }, isPrimary = true, enabled = canSave)
        }
        parental?.onDelete?.let { delete -> item { RetroButton("Delete Channel", delete) } }
    }
}

/** A searchable multi-select list (the Apple app's `FacetPickerView`). */
@Composable
internal fun FacetPickerPage(
    title: String,
    options: List<FacetOption>,
    selection: Set<String>,
    emptySelectionTitle: String = "Any",
    helpText: String? = null,
    onChange: (Set<String>) -> Unit,
) {
    var query by remember { mutableStateOf("") }
    val shown = if (query.isBlank()) options else options.filter { it.title.contains(query.trim(), ignoreCase = true) }
    SettingsPage(title) {
        helpText?.let { item { Note(it) } }
        item { Note(if (selection.isEmpty()) emptySelectionTitle else "${selection.size} selected") }
        if (selection.isNotEmpty()) item { RetroRow("Clear", { onChange(emptySet()) }) }
        if (options.size > SEARCH_THRESHOLD) {
            item { RetroTextField(query, { query = it }, "Search ${title.lowercase()}", Modifier, KeyboardType.Text) {} }
        }
        items(shown, key = { it.id }) { option ->
            CheckmarkRow(option.title, option.id in selection, {
                onChange(if (option.id in selection) selection - option.id else selection + option.id)
            }, detail = option.detail)
        }
    }
}

private fun summary(selection: Set<String>, options: List<FacetOption>): String {
    if (selection.isEmpty()) return "Any"
    val names = options.filter { it.id in selection }.map { it.title }
    return if (names.size == 1) names.first() else "${selection.size} selected"
}
