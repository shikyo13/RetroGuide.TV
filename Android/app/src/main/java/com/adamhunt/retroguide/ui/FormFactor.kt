package com.adamhunt.retroguide.ui

import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** Android TV (remote) or a phone or tablet (touch): the Apple app's tvOS and iOS layouts. */
enum class FormFactor {
    TV, TOUCH;

    val isTouch get() = this == TOUCH

    /** Space between the screen edge and content (tvOS overscan margins, or a small gap on touch screens). */
    val margin: Dp get() = if (isTouch) 16.dp else 40.dp
}

val LocalFormFactor = staticCompositionLocalOf { FormFactor.TV }
