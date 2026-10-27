package com.adamhunt.retroguide.ui.components

import android.view.KeyEvent as AndroidKeyEvent
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.nativeKeyCode
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import com.adamhunt.retroguide.ui.theme.LocalTheme

/**
 * A single-line text field in the theme's colors, for a remote: focus rests
 * on it like a row, Select starts typing (with the on-screen keyboard), and
 * Up or Down or the keyboard's Done stops. [startsEditing] opens it ready to
 * type (Search).
 */
@Composable
fun RetroTextField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    modifier: Modifier,
    keyboardType: KeyboardType,
    isSecret: Boolean = false,
    imeAction: ImeAction = ImeAction.Done,
    startsEditing: Boolean = false,
    onDone: () -> Unit,
) {
    val theme = LocalTheme.current
    val focusManager = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    val field = remember { FocusRequester() }
    val row = remember { FocusRequester() }
    var isEditing by remember { mutableStateOf(startsEditing) }
    var isRowFocused by remember { mutableStateOf(false) }
    var isFieldFocused by remember { mutableStateOf(false) }

    fun stopEditing() {
        isEditing = false
        keyboard?.hide()
        runCatching { row.requestFocus() }
    }

    LaunchedEffect(isEditing) {
        if (!isEditing) return@LaunchedEffect
        runCatching { field.requestFocus() }
        keyboard?.show()
    }
    Box(modifier) {
        OutlinedTextField(
            value = value,
            onValueChange = onValueChange,
            label = { androidx.compose.material3.Text(label) },
            singleLine = true,
            readOnly = !isEditing,
            modifier = Modifier
                .fillMaxWidth()
                .focusRequester(field)
                .focusProperties { canFocus = isEditing }
                .onFocusChanged {
                    // Typing ends when focus leaves the field (not before it first arrives).
                    if (isFieldFocused && !it.isFocused) isEditing = false
                    isFieldFocused = it.isFocused
                }
                .onPreviewKeyEvent { event ->
                    val direction = when (event.key.nativeKeyCode) {
                        AndroidKeyEvent.KEYCODE_DPAD_UP -> FocusDirection.Up
                        AndroidKeyEvent.KEYCODE_DPAD_DOWN -> FocusDirection.Down
                        else -> return@onPreviewKeyEvent false
                    }
                    if (event.type == KeyEventType.KeyDown) {
                        isEditing = false
                        focusManager.moveFocus(direction)
                    }
                    true
                },
            visualTransformation = if (isSecret) PasswordVisualTransformation() else VisualTransformation.None,
            keyboardOptions = KeyboardOptions(
                keyboardType = keyboardType,
                imeAction = imeAction,
                autoCorrectEnabled = false,
                showKeyboardOnFocus = false,
            ),
            keyboardActions = KeyboardActions(
                onDone = { stopEditing(); onDone() },
                onSearch = { stopEditing(); onDone() },
            ),
            colors = OutlinedTextFieldDefaults.colors(
                focusedTextColor = theme.textPrimary,
                unfocusedTextColor = theme.textPrimary,
                focusedBorderColor = theme.focusFill,
                unfocusedBorderColor = if (isRowFocused) theme.focusFill else theme.textSecondary,
                focusedLabelColor = theme.focusFill,
                unfocusedLabelColor = if (isRowFocused) theme.focusFill else theme.textSecondary,
                cursorColor = theme.accent,
            ),
        )
        if (!isEditing) {
            // Where focus rests until Select starts typing.
            Box(
                Modifier
                    .matchParentSize()
                    .focusRequester(row)
                    .onFocusChanged { isRowFocused = it.isFocused }
                    .focusable()
                    .onKeyEvent { event ->
                        val isSelect = event.key.nativeKeyCode == AndroidKeyEvent.KEYCODE_DPAD_CENTER ||
                            event.key.nativeKeyCode == AndroidKeyEvent.KEYCODE_ENTER
                        if (isSelect && event.type == KeyEventType.KeyUp) isEditing = true
                        isSelect
                    },
            )
        }
    }
}
