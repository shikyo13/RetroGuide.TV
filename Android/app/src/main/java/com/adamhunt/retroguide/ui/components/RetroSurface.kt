package com.adamhunt.retroguide.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.LocalContentColor
import androidx.tv.material3.Surface
import com.adamhunt.retroguide.ui.LocalFormFactor
import com.adamhunt.retroguide.ui.theme.Tokens

/**
 * A pressable surface that works with the remote and with touch: Compose for
 * TV's focus-driven Surface on Android TV (it reacts only to the D-pad), and
 * a plain tappable surface on phones and tablets.
 */
@Composable
fun RetroSurface(
    onClick: () -> Unit,
    shape: Shape,
    containerColor: Color,
    contentColor: Color,
    focusedContainerColor: Color,
    focusedContentColor: Color,
    modifier: Modifier = Modifier,
    focusedScale: Float = Tokens.Scale.FOCUSED,
    enabled: Boolean = true,
    content: @Composable BoxScope.() -> Unit,
) {
    if (LocalFormFactor.current.isTouch) {
        Box(
            modifier
                .clip(shape)
                .background(containerColor)
                .clickable(enabled = enabled, onClick = onClick)
                .then(if (enabled) Modifier else Modifier.alpha(Tokens.Opacity.MUTED)),
        ) {
            CompositionLocalProvider(LocalContentColor provides contentColor) { content() }
        }
    } else {
        Surface(
            onClick = onClick,
            enabled = enabled,
            modifier = modifier,
            shape = ClickableSurfaceDefaults.shape(shape),
            scale = ClickableSurfaceDefaults.scale(focusedScale = focusedScale),
            colors = ClickableSurfaceDefaults.colors(
                containerColor = containerColor,
                contentColor = contentColor,
                focusedContainerColor = focusedContainerColor,
                focusedContentColor = focusedContentColor,
            ),
            content = content,
        )
    }
}
