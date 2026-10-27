package com.adamhunt.retroguide.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.Surface
import androidx.tv.material3.Text
import com.adamhunt.retroguide.ui.theme.Audience
import com.adamhunt.retroguide.ui.theme.LocalTheme
import com.adamhunt.retroguide.ui.theme.Tokens
import com.adamhunt.retroguide.ui.theme.Typography

/** A pill button that fills with the theme's focus color when focused (the Apple app's `.retro` style). */
@Composable
fun RetroButton(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    isPrimary: Boolean = false,
    enabled: Boolean = true,
) {
    val theme = LocalTheme.current
    Surface(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier.defaultMinSize(minHeight = Tokens.Control.minimumHeight),
        shape = ClickableSurfaceDefaults.shape(RoundedCornerShape(percent = 50)),
        scale = ClickableSurfaceDefaults.scale(focusedScale = Tokens.Scale.FOCUSED),
        colors = ClickableSurfaceDefaults.colors(
            containerColor = if (isPrimary) theme.accent.copy(alpha = Tokens.Opacity.MUTED) else theme.surfaceRaised,
            contentColor = theme.textPrimary,
            focusedContainerColor = theme.focusFill,
            focusedContentColor = theme.textOnFocus,
        ),
    ) {
        Box(Modifier.padding(horizontal = Tokens.Spacing.lg, vertical = Tokens.Spacing.sm), contentAlignment = Alignment.Center) {
            Text(title, style = Typography.bodyEmphasis, maxLines = 1)
        }
    }
}

/** A full-width row button for lists (the Apple app's `.retroRow` style). */
@Composable
fun RetroRow(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    detail: String? = null,
    trailing: String? = null,
) {
    val theme = LocalTheme.current
    Surface(
        onClick = onClick,
        modifier = modifier.fillMaxWidth().defaultMinSize(minHeight = Tokens.Control.minimumHeight),
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
            Modifier.padding(horizontal = Tokens.Spacing.md, vertical = Tokens.Spacing.sm),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.md),
        ) {
            Column(Modifier.weight(1f)) {
                Text(title, style = Typography.bodyEmphasis, maxLines = 1, overflow = TextOverflow.Ellipsis)
                detail?.let { Text(it, style = Typography.caption, maxLines = 1, overflow = TextOverflow.Ellipsis) }
            }
            trailing?.let { Text(it, style = Typography.callout, maxLines = 1) }
        }
    }
}

/** A rounded surface for grouping content (the Apple app's `.panel()`). */
@Composable
fun Panel(
    modifier: Modifier = Modifier,
    padding: Dp = Tokens.Spacing.lg,
    color: Color? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val theme = LocalTheme.current
    Column(
        modifier
            .clip(RoundedCornerShape(Tokens.Radius.large))
            .background(color ?: theme.surface.copy(alpha = Tokens.Opacity.SCRIM))
            .padding(padding),
        verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.sm),
        content = content,
    )
}

/** Channel number over its call sign. */
@Composable
fun ChannelBadge(number: Int, callSign: String, modifier: Modifier = Modifier, large: Boolean = false) {
    val theme = LocalTheme.current
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(number.toString(), style = if (large) Typography.title else Typography.channelNumber, color = theme.accent)
        Text(callSign, style = Typography.callSign, color = theme.accentSecondary, maxLines = 1)
    }
}

/** The content rating in a small outlined chip, in its audience's color. */
@Composable
fun RatingChip(rating: String?, audience: Audience) {
    val theme = LocalTheme.current
    val text = rating?.takeIf { it.isNotBlank() } ?: return
    val color = theme.color(audience)
    Text(
        text,
        style = Typography.micro,
        color = color,
        modifier = Modifier
            .clip(RoundedCornerShape(Tokens.Radius.small))
            .background(color.copy(alpha = Tokens.Opacity.SUBTLE))
            .padding(PaddingValues(horizontal = Tokens.Spacing.xs, vertical = Tokens.Spacing.hairline)),
    )
}

/** A thin progress bar in the accent color. */
@Composable
fun ProgressTrack(progress: Float, modifier: Modifier = Modifier, height: Dp = Tokens.Spacing.xs) {
    val theme = LocalTheme.current
    Box(
        modifier
            .height(height)
            .clip(RoundedCornerShape(percent = 50))
            .background(theme.textSecondary.copy(alpha = Tokens.Opacity.SUBTLE)),
    ) {
        Box(
            Modifier
                .fillMaxWidth(progress.coerceIn(0f, 1f))
                .height(height)
                .background(theme.accent),
        )
    }
}
