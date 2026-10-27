package com.adamhunt.retroguide.ui.components

import android.view.KeyEvent as AndroidKeyEvent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.nativeKeyCode
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.tv.material3.Text
import com.adamhunt.retroguide.core.Choice
import com.adamhunt.retroguide.ui.theme.LocalTheme
import com.adamhunt.retroguide.ui.theme.Tokens
import com.adamhunt.retroguide.ui.theme.Typography

/** A small all-caps heading over a group of rows (the Apple app's `SettingsSection` title). */
@Composable
fun SectionHeader(title: String, modifier: Modifier = Modifier) {
    Text(
        title.uppercase(), style = Typography.captionEmphasis, color = LocalTheme.current.accentSecondary,
        modifier = modifier.padding(top = Tokens.Spacing.md, start = Tokens.Spacing.xs),
    )
}

/** Secondary text explaining the rows around it. */
@Composable
fun Note(text: String, modifier: Modifier = Modifier, emphasized: Boolean = false) {
    val theme = LocalTheme.current
    Text(
        text, style = Typography.body, color = if (emphasized) theme.accent else theme.textSecondary,
        modifier = modifier.fillMaxWidth().padding(horizontal = Tokens.Spacing.xs),
    )
}

/**
 * A row showing a setting's value that opens its choices below it when
 * selected (the Apple app's `OptionMenu`); picking one closes them.
 */
@Composable
fun ChoiceRow(
    title: String,
    choices: List<Choice>,
    selectedID: String?,
    onSelect: (Choice) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    var isOpen by remember { mutableStateOf(false) }
    var wasOpened by remember { mutableStateOf(false) }
    val header = remember { FocusRequester() }
    val value = choices.firstOrNull { it.id == selectedID }?.title
    // Closing the choices returns focus to the row that opened them.
    LaunchedEffect(isOpen) {
        if (isOpen) wasOpened = true else if (wasOpened) runCatching { header.requestFocus() }
    }
    Column(modifier) {
        RetroRow(
            title,
            onClick = { if (enabled) isOpen = !isOpen },
            modifier = Modifier.focusRequester(header),
            trailing = listOfNotNull(value, if (enabled) (if (isOpen) "▴" else "▾") else null).joinToString("  "),
        )
        if (isOpen) {
            for (choice in choices) {
                RetroRow(
                    choice.title,
                    onClick = {
                        isOpen = false
                        if (choice.id != selectedID) onSelect(choice)
                    },
                    modifier = Modifier.padding(start = Tokens.Spacing.lg, top = Tokens.Spacing.xxs),
                    trailing = if (choice.id == selectedID) "✓" else null,
                )
            }
        }
    }
}

/**
 * A row the remote's Left and Right adjust (the Apple app's remote adjusters);
 * Select runs [onSelect]. [onAdjust] gets −1 or +1 and how many presses in a row.
 */
@Composable
fun AdjustableRow(
    title: String,
    value: String,
    onAdjust: (direction: Int, repeatCount: Int) -> Unit,
    onSelect: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var isFocused by remember { mutableStateOf(false) }
    var lastPress by remember { mutableStateOf(0L to 0) }
    var repeatCount by remember { mutableStateOf(0) }
    RetroRow(
        title,
        onClick = onSelect,
        trailing = if (isFocused) "◀ $value ▶" else value,
        modifier = modifier
            .onFocusChanged { isFocused = it.isFocused }
            .onPreviewKeyEvent { event ->
                val direction = when (event.key.nativeKeyCode) {
                    AndroidKeyEvent.KEYCODE_DPAD_LEFT -> -1
                    AndroidKeyEvent.KEYCODE_DPAD_RIGHT -> 1
                    else -> return@onPreviewKeyEvent false
                }
                if (event.type == KeyEventType.KeyDown) {
                    val now = System.currentTimeMillis()
                    val (time, previous) = lastPress
                    repeatCount = if (previous == direction && now - time < REPEAT_WINDOW_MS) repeatCount + 1 else 0
                    lastPress = now to direction
                    onAdjust(direction, repeatCount)
                }
                true
            },
    )
}

/** Presses closer together than this count as holding the button. */
private const val REPEAT_WINDOW_MS = 350L

/** A choice in a list, checked when selected (the Apple app's `CheckmarkRow`). */
@Composable
fun CheckmarkRow(
    title: String,
    isSelected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    detail: String? = null,
) {
    RetroRow(title, onClick, modifier, detail = detail, trailing = if (isSelected) "✓" else "")
}

/** A RetroGuide Pro feature without Pro: opens the upgrade page (the Apple app's `ProLockedRow`). */
@Composable
fun ProLockedRow(title: String, onOpenPro: () -> Unit, modifier: Modifier = Modifier) {
    RetroRow(title, onOpenPro, modifier, trailing = PRO_BADGE)
}

/** Marks rows that need RetroGuide Pro. */
const val PRO_BADGE = "Pro 🔒"
