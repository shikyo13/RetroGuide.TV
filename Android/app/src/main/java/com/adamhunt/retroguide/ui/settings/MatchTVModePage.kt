package com.adamhunt.retroguide.ui.settings

import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import com.adamhunt.retroguide.AppModel
import com.adamhunt.retroguide.player.MatchTVMode
import com.adamhunt.retroguide.ui.components.CheckmarkRow
import com.adamhunt.retroguide.ui.components.Note

/** Whether the TV switches its refresh rate for each program (the Apple app's `DisplayMatchingPickerView`). */
@Composable
fun MatchTVModePage(app: AppModel) {
    val current by app.matchTVMode.collectAsState()
    SettingsPage("Match TV Mode") {
        items(MatchTVMode.entries, key = { it.name }) { mode ->
            CheckmarkRow(mode.title, current == mode, { app.setMatchTVMode(mode) }, detail = mode.explanation)
        }
        item { Note("HDR programs play in standard range on Android TV for now.") }
        item { Note("Your TV may also need its own match-content or frame-rate setting turned on.") }
    }
}
