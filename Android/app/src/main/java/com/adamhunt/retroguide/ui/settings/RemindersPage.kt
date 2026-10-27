package com.adamhunt.retroguide.ui.settings

import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalContext
import com.adamhunt.retroguide.AppModel
import com.adamhunt.retroguide.ui.components.Note
import com.adamhunt.retroguide.ui.components.ProLockedRow
import com.adamhunt.retroguide.ui.components.RetroRow
import com.adamhunt.retroguide.ui.components.SectionHeader
import com.adamhunt.retroguide.ui.watch.ScheduleFormatting

/** Upcoming reminders, each cancelled by selecting it (the Apple app's `RemindersView`). */
@Composable
fun RemindersPage(app: AppModel, navigator: SettingsNavigator) {
    val isPro by app.isPro.collectAsState()
    val pending by app.reminders.pending.collectAsState()
    SettingsPage("Program reminders", navigator) {
        item { Note("Browse ahead in the guide, focus a program, then press Up and choose Remind me. Reminders never change channels automatically.") }
        val notifications = app.reminders.notifications
        if (notifications == null) {
            item { Note("Reminders appear while RetroGuide.TV is open.") }
        } else {
            item { Note("Reminders arrive as notifications, even when RetroGuide.TV is closed.") }
            if (!notifications.isOnTime) {
                item {
                    val context = LocalContext.current
                    RetroRow("Remind me right on time", { context.startActivity(notifications.onTimeSettingsIntent()) },
                        detail = "Without this, Android may deliver reminders a few minutes late.", trailing = "Allow")
                }
            }
        }
        if (!isPro) item { ProLockedRow("Program reminders", { navigator.open(SettingsRoute.Pro) }) }
        if (pending.isEmpty()) {
            item { Note("No upcoming reminders") }
        } else {
            item { SectionHeader("Upcoming") }
            items(pending, key = { it.id }) { reminder ->
                RetroRow(reminder.title, { app.reminders.remove(reminder.id) },
                    detail = "${ScheduleFormatting.dayAndTime(reminder.start)} · ${reminder.channelName}", trailing = "Cancel")
            }
        }
    }
}
