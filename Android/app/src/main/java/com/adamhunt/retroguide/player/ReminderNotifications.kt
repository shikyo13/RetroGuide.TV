package com.adamhunt.retroguide.player

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.adamhunt.retroguide.R
import com.adamhunt.retroguide.core.ReminderInfo

/**
 * Program reminders as notifications on phones and tablets (the Apple app's
 * iPhone and iPad reminders): an alarm at each program's start posts a
 * notification that opens the app on that channel.
 */
class ReminderNotifications(private val context: Context) {
    private object Keys {
        const val CHANNEL = "reminders"
        const val CHANNEL_NAME = "Program reminders"
        const val TITLE = "title"
        const val TEXT = "text"
        const val LINK = "link"
        const val ID = "id"
        const val CHANNEL_LINK = "retroguide://channel?id="
    }

    private val alarms = context.getSystemService(AlarmManager::class.java)

    /** Whether notifications may be posted (Android 13 and later ask the viewer once). */
    val isAllowed: Boolean
        get() = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    /** Whether reminders come exactly on time (Android 12 and later let the viewer allow it). */
    val isOnTime: Boolean
        get() = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarms.canScheduleExactAlarms()

    /** Opens the system screen where the viewer allows on-time reminders. */
    fun onTimeSettingsIntent(): Intent =
        Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:${context.packageName}"))

    /**
     * Replaces the scheduled alarms with [pending]. Reminders that left the list
     * because their program started keep their alarm: it is about to post.
     */
    fun schedule(pending: List<ReminderInfo>, previous: List<ReminderInfo>) {
        val now = System.currentTimeMillis()
        val kept = pending.map { it.id }.toSet()
        for (reminder in previous) {
            val hasStarted = (reminder.start * MILLIS_PER_SECOND).toLong() <= now
            if (reminder.id !in kept && !hasStarted) alarms.cancel(alarmIntent(reminder))
        }
        if (!isAllowed) return
        for (reminder in pending) {
            val at = (reminder.start * MILLIS_PER_SECOND).toLong()
            if (at <= now) continue
            val intent = alarmIntent(reminder)
            if (isOnTime) {
                alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent)
            } else {
                alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent)
            }
        }
    }

    private fun alarmIntent(reminder: ReminderInfo): PendingIntent {
        val intent = Intent(context, ReminderReceiver::class.java)
            .putExtra(Keys.ID, reminder.id)
            .putExtra(Keys.TITLE, reminder.title)
            .putExtra(Keys.TEXT, "Starting now on ${reminder.channelName}")
            .putExtra(Keys.LINK, Keys.CHANNEL_LINK + Uri.encode(reminder.channelID))
        return PendingIntent.getBroadcast(context, reminder.id.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    /** Posts a reminder's notification when its alarm goes off. */
    class ReminderReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(NotificationChannel(Keys.CHANNEL, Keys.CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH))
            val open = Intent(Intent.ACTION_VIEW, Uri.parse(intent.getStringExtra(Keys.LINK))).setPackage(context.packageName)
            val tap = PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val notification = NotificationCompat.Builder(context, Keys.CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(intent.getStringExtra(Keys.TITLE))
                .setContentText(intent.getStringExtra(Keys.TEXT))
                .setContentIntent(tap)
                .setAutoCancel(true)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .build()
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED ||
                Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU
            ) {
                NotificationManagerCompat.from(context).notify(intent.getStringExtra(Keys.ID).hashCode(), notification)
            }
        }
    }

    private companion object {
        const val MILLIS_PER_SECOND = 1000
    }
}
