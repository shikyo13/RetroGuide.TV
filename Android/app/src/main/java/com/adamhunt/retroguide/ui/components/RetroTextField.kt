package com.adamhunt.retroguide.ui.components

import android.view.KeyEvent as AndroidKeyEvent
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.nativeKeyCode
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import com.adamhunt.retroguide.ui.theme.LocalTheme

/** A single-line text field in the theme's colors; the remote's keyboard opens when it's selected. */
@Composable
fun RetroTextField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    modifier: Modifier,
    keyboardType: KeyboardType,
    isSecret: Boolean = false,
    imeAction: ImeAction = ImeAction.Done,
    onDone: () -> Unit,
) {
    val theme = LocalTheme.current
    val focusManager = LocalFocusManager.current
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { androidx.compose.material3.Text(label) },
        singleLine = true,
        // On a remote, Up and Down leave the field rather than move its cursor.
        modifier = modifier.fillMaxWidth().onPreviewKeyEvent { event ->
            val direction = when (event.key.nativeKeyCode) {
                AndroidKeyEvent.KEYCODE_DPAD_UP -> FocusDirection.Up
                AndroidKeyEvent.KEYCODE_DPAD_DOWN -> FocusDirection.Down
                else -> return@onPreviewKeyEvent false
            }
            if (event.type == KeyEventType.KeyDown) focusManager.moveFocus(direction)
            true
        },
        visualTransformation = if (isSecret) PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None,
        keyboardOptions = KeyboardOptions(keyboardType = keyboardType, imeAction = imeAction, autoCorrectEnabled = false),
        keyboardActions = KeyboardActions(onDone = { onDone() }, onSearch = { onDone() }),
        colors = OutlinedTextFieldDefaults.colors(
            focusedTextColor = theme.textPrimary,
            unfocusedTextColor = theme.textPrimary,
            focusedBorderColor = theme.focusFill,
            unfocusedBorderColor = theme.textSecondary,
            focusedLabelColor = theme.focusFill,
            unfocusedLabelColor = theme.textSecondary,
            cursorColor = theme.accent,
        ),
    )
}
