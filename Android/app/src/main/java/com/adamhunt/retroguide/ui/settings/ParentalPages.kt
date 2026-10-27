package com.adamhunt.retroguide.ui.settings

import androidx.activity.compose.BackHandler
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
import com.adamhunt.retroguide.core.ChannelDraft
import com.adamhunt.retroguide.core.Choice
import com.adamhunt.retroguide.core.ParentalDraft
import com.adamhunt.retroguide.core.ParentalEditor
import com.adamhunt.retroguide.ui.components.CheckmarkRow
import com.adamhunt.retroguide.ui.components.ChoiceRow
import com.adamhunt.retroguide.ui.components.Note
import com.adamhunt.retroguide.ui.components.ProLockedRow
import com.adamhunt.retroguide.ui.components.RetroButton
import com.adamhunt.retroguide.ui.components.RetroRow
import com.adamhunt.retroguide.ui.components.RetroTextField
import com.adamhunt.retroguide.ui.components.SectionHeader
import kotlinx.coroutines.launch

/** Settings are locked until the parent enters the PIN (the Apple app's `ParentalPINView`). */
@Composable
fun ParentalPinPage(app: AppModel, onCancel: () -> Unit) {
    val message by app.parentalLock.message.collectAsState()
    var pin by remember { mutableStateOf("") }
    fun unlock() {
        if (!app.parentalLock.isValid(pin)) return
        app.authorizeParental(pin)
        pin = ""
    }
    SettingsPage("Parental Lock") {
        item { Note("Enter your PIN to change settings. Content restrictions stay active while you make changes.") }
        item { RetroTextField(pin, { pin = it.filter(Char::isDigit).take(4) }, "Four-digit PIN", Modifier, KeyboardType.NumberPassword, isSecret = true) { unlock() } }
        item { RetroButton("Unlock Settings", ::unlock, isPrimary = true, enabled = app.parentalLock.isValid(pin)) }
        item { RetroButton("Cancel", onCancel) }
        message?.let { item { Note(it, emphasized = true) } }
    }
}

/** A page inside Parental Controls (kept within one screen so the draft is shared). */
private sealed interface ParentalPage {
    data object Channels : ParentalPage
    data class Channel(val index: Int?) : ParentalPage
    data object Ratings : ParentalPage
    data object Libraries : ParentalPage
    data object LibraryPicker : ParentalPage
    data object AllowedContent : ParentalPage
    data object Collections : ParentalPage
    data object AllowedTitles : ParentalPage
    data object Genres : ParentalPage
    data object GenrePicker : ParentalPage
    data object BlockedTitles : ParentalPage
}

/**
 * Restrictions for this device (the Apple app's `ParentalControlsView` and its
 * pages): what's allowed, a custom lineup, and a PIN that locks Settings.
 * Nothing changes until Save.
 */
@Composable
fun ParentalControlsPage(app: AppModel, navigator: SettingsNavigator) {
    val scope = rememberCoroutineScope()
    val isPro by app.isPro.collectAsState()
    var editor by remember { mutableStateOf<ParentalEditor?>(null) }
    var draft by remember { mutableStateOf(ParentalDraft()) }
    var pages by remember { mutableStateOf(listOf<ParentalPage>()) }
    var pin by remember { mutableStateOf("") }
    var confirmation by remember { mutableStateOf("") }
    var message by remember { mutableStateOf<String?>(null) }
    var isSaving by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        editor = runCatching { app.core.parentalEditor() }.getOrNull()
        editor?.let { draft = it.draft }
    }
    fun open(page: ParentalPage) { pages = pages + page }
    fun back() { pages = pages.dropLast(1) }
    val choices = editor ?: run {
        SettingsPage("Parental Controls") { item { Note("Loading your libraries…") } }
        return
    }

    pages.lastOrNull()?.let { page ->
        BackHandler(onBack = ::back)
        when (page) {
            ParentalPage.Channels -> ParentalChannels(draft, isPro, { draft = it }, ::open, onOpenPro = { navigator.open(SettingsRoute.Pro) })
            is ParentalPage.Channel -> {
                val existing = page.index?.let { draft.customChannels.getOrNull(it) }
                ChannelEditorPage(app, navigator, existing ?: ChannelDraft(), ParentalChannelEditing(
                    policy = draft,
                    onSave = { channel ->
                        draft = draft.copy(customChannels = page.index?.let { index ->
                            draft.customChannels.toMutableList().also { it[index] = channel }
                        } ?: (draft.customChannels + channel))
                        back()
                    },
                    onDelete = page.index?.let { index ->
                        {
                            draft = draft.copy(customChannels = draft.customChannels.filterIndexed { i, _ -> i != index })
                            back()
                        }
                    },
                ))
            }
            ParentalPage.Ratings -> ParentalRatings(draft, choices) { draft = it }
            ParentalPage.Libraries -> SettingsPage("Libraries") {
                item { CheckmarkRow("All connected libraries", draft.allLibraries, { draft = draft.copy(allLibraries = true) }) }
                item { CheckmarkRow("Selected libraries", !draft.allLibraries, { draft = draft.copy(allLibraries = false) }) }
                if (!draft.allLibraries) {
                    item { RetroRow("Choose Libraries", { open(ParentalPage.LibraryPicker) }, trailing = "${draft.libraryIDs.size} selected") }
                }
            }
            ParentalPage.LibraryPicker -> FacetPickerPage(
                "Choose Libraries", choices.libraries, draft.libraryIDs.toSet(), "None selected",
                "Only these libraries can supply content. Each library lists the server it belongs to.",
            ) { draft = draft.copy(libraryIDs = it.sorted()) }
            ParentalPage.AllowedContent -> ParentalAllowedContent(draft, { draft = it }, ::open)
            ParentalPage.Collections -> FacetPickerPage(
                "Collections", choices.collections, draft.collectionNames.toSet(), "None selected",
                "Matching copies of titles in these collections are included. Your library and rating limits still apply.",
            ) { draft = draft.copy(collectionNames = it.sorted()) }
            ParentalPage.AllowedTitles -> FacetPickerPage(
                "Shows and Movies", choices.titles, draft.allowedTitleIDs.toSet(), "None selected",
                "Selecting a show includes its episodes. Matching copies on other servers are included, within your library and rating limits.",
            ) { draft = draft.copy(allowedTitleIDs = it.sorted()) }
            ParentalPage.Genres -> SettingsPage("Allowed Genres") {
                item { CheckmarkRow("All genres", draft.allGenres, { draft = draft.copy(allGenres = true) }) }
                item { CheckmarkRow("Selected genres", !draft.allGenres, { draft = draft.copy(allGenres = false) }) }
                if (!draft.allGenres) {
                    item { RetroRow("Choose Genres", { open(ParentalPage.GenrePicker) }, trailing = "${draft.genreNames.size} selected") }
                }
                item { Note("When Selected genres is enabled, each copy needs a matching server tag. Your rating, library and title restrictions also apply.") }
                item { Note("Animation and Documentary do not necessarily mean suitable for children or educational. For a specific learning lineup, select a curated collection in Allowed Content.") }
            }
            ParentalPage.GenrePicker -> FacetPickerPage(
                "Genres", choices.genres, draft.genreNames.toSet(), "None selected. No content allowed.",
                "A title needs at least one selected genre. Titles without a matching tag are excluded.",
            ) { draft = draft.copy(genreNames = it.sorted()) }
            ParentalPage.BlockedTitles -> FacetPickerPage(
                "Blocked Shows and Movies", choices.titles, draft.blockedTitleIDs.toSet(), "None selected",
                "Blocked shows and movies are hidden from every channel, including matching copies on other servers.",
            ) { draft = draft.copy(blockedTitleIDs = it.sorted()) }
        }
        return
    }

    val needsPIN = !app.parentalLock.hasPIN && draft.isEnabled
    fun save() {
        if (needsPIN && pin != confirmation) {
            message = "The PINs do not match."
            return
        }
        isSaving = true
        scope.launch {
            message = app.saveParental(draft, if (needsPIN) pin else null)
            isSaving = false
            if (message == null) navigator.back()
        }
    }
    SettingsPage("Parental Controls", navigator) {
        item {
            CheckmarkRow("Enable parental controls", draft.isEnabled, { draft = draft.copy(isEnabled = !draft.isEnabled) },
                detail = "Limit content and lock settings on this device.")
        }
        item { SectionHeader("Content restrictions") }
        item {
            val summary = if (!draft.usesCustomLineup) "Regular lineup" else
                if (draft.customChannels.size == 1) "1 custom channel" else "${draft.customChannels.size} custom channels"
            RetroRow("Channels", { open(ParentalPage.Channels) }, trailing = summary)
        }
        item { RetroRow("Ratings", { open(ParentalPage.Ratings) }, trailing = "${draft.maximumMovieRating} · ${draft.maximumTVRating}") }
        item { RetroRow("Libraries", { open(ParentalPage.Libraries) }, trailing = if (draft.allLibraries) "All" else "${draft.libraryIDs.size} selected") }
        item {
            RetroRow("Allowed Content", { open(ParentalPage.AllowedContent) }, trailing = when {
                draft.selectedContentOnly -> "Selected only"
                draft.allGenres -> "All within limits"
                draft.genreNames.isEmpty() -> "No genres selected"
                else -> "Genres selected"
            })
        }
        item {
            RetroRow("Blocked Shows and Movies", { open(ParentalPage.BlockedTitles) },
                trailing = if (draft.blockedTitleIDs.isEmpty()) "None" else "${draft.blockedTitleIDs.size} selected")
        }
        if (needsPIN) {
            item { SectionHeader("Create PIN") }
            item { RetroTextField(pin, { pin = it.filter(Char::isDigit).take(4) }, "Four-digit PIN", Modifier, KeyboardType.NumberPassword, isSecret = true) {} }
            item { RetroTextField(confirmation, { confirmation = it.filter(Char::isDigit).take(4) }, "Confirm PIN", Modifier, KeyboardType.NumberPassword, isSecret = true) {} }
            item { Note("Use this PIN to change settings or turn off parental controls. Keep it somewhere safe.") }
        }
        message?.let { item { Note(it, emphasized = true) } }
        item { RetroButton(if (isSaving) "Saving…" else "Save", ::save, isPrimary = true, enabled = !isSaving) }
        item { RetroButton("Cancel", navigator::back, enabled = !isSaving) }
    }
}

@Composable
private fun ParentalChannels(draft: ParentalDraft, isPro: Boolean, onChange: (ParentalDraft) -> Unit, open: (ParentalPage) -> Unit, onOpenPro: () -> Unit) {
    SettingsPage("Channels") {
        item {
            CheckmarkRow("Regular lineup", !draft.usesCustomLineup, { onChange(draft.copy(usesCustomLineup = false)) },
                detail = "Your existing channels with parental restrictions applied.")
        }
        item {
            CheckmarkRow("Custom lineup", draft.usesCustomLineup, { onChange(draft.copy(usesCustomLineup = true)) },
                detail = "Only the channels you create here.")
        }
        if (draft.usesCustomLineup) {
            item { SectionHeader("Your channels") }
            items(draft.customChannels.size) { index ->
                RetroRow(draft.customChannels[index].name, { open(ParentalPage.Channel(index)) }, trailing = "Edit")
            }
            item {
                // The Kit's `ProAccess.FreeLimits.customChannels` is one channel.
                if (isPro || draft.customChannels.isEmpty()) {
                    RetroRow("Add Channel", { open(ParentalPage.Channel(null)) })
                } else {
                    ProLockedRow("Add another channel", onOpenPro)
                }
            }
            if (draft.customChannels.isEmpty()) {
                item { Note("Add your first channel. An empty custom lineup shows no channels.") }
            }
        }
        item { Note("This lineup takes over when parental controls are on. Turning them off restores your regular lineup. All content restrictions still apply.") }
        item { Note("Save on the Parental Controls screen to apply your changes. Cancel there discards them.") }
    }
}

@Composable
private fun ParentalRatings(draft: ParentalDraft, editor: ParentalEditor, onChange: (ParentalDraft) -> Unit) {
    SettingsPage("Ratings") {
        item { SectionHeader("U.S. ratings") }
        item {
            ChoiceRow("Movies", editor.movieRatings.map { Choice(it, it) }, draft.maximumMovieRating, { onChange(draft.copy(maximumMovieRating = it.id)) })
        }
        item {
            ChoiceRow("TV Shows", editor.tvRatings.map { Choice(it, it) }, draft.maximumTVRating, { onChange(draft.copy(maximumTVRating = it.id)) })
        }
        item { Note("Choose the highest rating allowed for each type of content.") }
        item { SectionHeader("Other ratings") }
        item {
            CheckmarkRow("Allow unrated or unrecognized content", draft.allowsUnrated, { onChange(draft.copy(allowsUnrated = !draft.allowsUnrated)) })
        }
        item {
            Note("Ratings come from your servers. Content without a U.S. rating, including other countries' ratings, is blocked unless you allow it here.")
        }
    }
}

@Composable
private fun ParentalAllowedContent(draft: ParentalDraft, onChange: (ParentalDraft) -> Unit, open: (ParentalPage) -> Unit) {
    SettingsPage("Allowed Content") {
        item { CheckmarkRow("All shows and movies within limits", !draft.selectedContentOnly, { onChange(draft.copy(selectedContentOnly = false)) }) }
        item { CheckmarkRow("Selected collections, shows and movies", draft.selectedContentOnly, { onChange(draft.copy(selectedContentOnly = true)) }) }
        if (draft.selectedContentOnly) {
            item { SectionHeader("Choose content") }
            item { RetroRow("Collections", { open(ParentalPage.Collections) }, trailing = "${draft.collectionNames.size} selected") }
            item { RetroRow("Shows and Movies", { open(ParentalPage.AllowedTitles) }, trailing = "${draft.allowedTitleIDs.size} selected") }
        }
        item { SectionHeader("Genres") }
        item { RetroRow("Allowed Genres", { open(ParentalPage.Genres) }, trailing = if (draft.allGenres) "All" else "${draft.genreNames.size} selected") }
        item {
            Note("Your genre, library and rating limits always apply. New episodes and additions to selected collections follow the same limits.")
        }
    }
}
