package com.adamhunt.retroguide.widget

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.ColorFilter
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.ActionParameters
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontFamily
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.adamhunt.retroguide.R
import com.adamhunt.retroguide.ui.theme.Theme
import com.adamhunt.retroguide.ui.theme.ThemeId
import com.adamhunt.retroguide.ui.watch.ScheduleFormatting

/** Sizes of the widget (the Apple app's `WidgetStyle`). */
private object WidgetStyle {
    val padding = 12.dp
    val spacing = 4.dp
    val corner = 12.dp
    val stillWidth = 128.dp
    val stillHeight = 72.dp
    val logoHeight = 28.dp
    val button = 32.dp
    val osdSize = 13.sp
    val titleSize = 15.sp
    val detailSize = 12.sp
    const val STILL_OPACITY_ALPHA = 0.6f
}

/**
 * "What's On" on the home screen (the Apple app's widget): the channel watched
 * last with what's on it now, an episode still, and buttons to flip through
 * the next channels. Tapping it opens the app on that channel.
 */
class WhatsOnWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val store = WhatsOnStore(context)
        val saved = store.load()
        val theme = Theme.of(themeOf(context))
        provideContent { Content(context, store, saved, theme) }
    }

    @Composable
    private fun Content(context: Context, store: WhatsOnStore, saved: WhatsOnStore.Saved?, theme: Theme) {
        val now = System.currentTimeMillis() / 1000.0
        val channels = saved?.channels.orEmpty().filter { it.programAt(now) != null }
        val background = GlanceModifier.fillMaxSize().background(theme.surface).cornerRadius(WidgetStyle.corner)
        if (channels.isEmpty()) {
            Column(background.padding(WidgetStyle.padding), verticalAlignment = Alignment.CenterVertically, horizontalAlignment = Alignment.CenterHorizontally) {
                Text("RetroGuide.TV", style = TextStyle(color = ColorProvider(theme.textPrimary), fontWeight = FontWeight.Bold, fontSize = WidgetStyle.titleSize))
                Text("Open RetroGuide.TV to refresh your channels", style = TextStyle(color = ColorProvider(theme.textSecondary), fontSize = WidgetStyle.detailSize))
            }
            return
        }
        val channel = channels[Math.floorMod(store.offset, channels.size)]
        val program = channel.programAt(now) ?: return
        val open = Intent(Intent.ACTION_VIEW, Uri.parse(CHANNEL_LINK + Uri.encode(channel.id))).setPackage(context.packageName)
        Row(background.padding(WidgetStyle.padding).clickable(actionStartActivity(open)), verticalAlignment = Alignment.CenterVertically) {
            Box(GlanceModifier.size(WidgetStyle.stillWidth, WidgetStyle.stillHeight).cornerRadius(WidgetStyle.corner).background(Color.Black)) {
                store.artwork(program.stillFile)?.let { file ->
                    BitmapFactory.decodeFile(file.path)?.let { bitmap ->
                        Image(ImageProvider(bitmap), contentDescription = null, contentScale = ContentScale.Crop, modifier = GlanceModifier.fillMaxSize())
                    }
                }
                Text(
                    "${channel.number} ${channel.callSign}",
                    style = TextStyle(color = ColorProvider(theme.osd), fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, fontSize = WidgetStyle.osdSize),
                    modifier = GlanceModifier.padding(WidgetStyle.spacing),
                )
            }
            Spacer(GlanceModifier.width(WidgetStyle.padding))
            Column(GlanceModifier.defaultWeight().fillMaxHeight()) {
                val logo = store.artwork(program.logoFile)?.let { BitmapFactory.decodeFile(it.path) }
                if (logo != null) {
                    Image(ImageProvider(logo), contentDescription = program.title, contentScale = ContentScale.Fit,
                        modifier = GlanceModifier.height(WidgetStyle.logoHeight).fillMaxWidth())
                } else {
                    Text(program.title, maxLines = 1, style = TextStyle(color = ColorProvider(theme.textPrimary), fontWeight = FontWeight.Bold, fontSize = WidgetStyle.titleSize))
                }
                program.episode?.let {
                    Text(it, maxLines = 1, style = TextStyle(color = ColorProvider(theme.textPrimary), fontSize = WidgetStyle.detailSize))
                }
                Text(
                    "${ScheduleFormatting.time(program.start)} – ${ScheduleFormatting.time(program.end)}",
                    style = TextStyle(color = ColorProvider(theme.accent), fontFamily = FontFamily.Monospace, fontSize = WidgetStyle.detailSize),
                )
                Spacer(GlanceModifier.defaultWeight())
                if (channels.size > 1 && saved?.pinned != true) {
                    Row(GlanceModifier.fillMaxWidth(), horizontalAlignment = Alignment.End) {
                        FlipButton("◀", theme, actionRunCallback<FlipBack>())
                        Spacer(GlanceModifier.width(WidgetStyle.spacing))
                        FlipButton("▶", theme, actionRunCallback<FlipForward>())
                    }
                }
            }
        }
    }

    @Composable
    private fun FlipButton(symbol: String, theme: Theme, action: androidx.glance.action.Action) {
        Box(
            GlanceModifier.size(WidgetStyle.button).cornerRadius(WidgetStyle.button / 2).background(theme.surfaceRaised).clickable(action),
            contentAlignment = Alignment.Center,
        ) {
            Text(symbol, style = TextStyle(color = ColorProvider(theme.textPrimary), fontSize = WidgetStyle.detailSize))
        }
    }

    companion object {
        private const val CHANNEL_LINK = "retroguide://channel?id="
        private const val THEME_PREFERENCES = "watching"
        private const val THEME_KEY = "theme"

        /** The app's chosen theme (the widget follows it, as on Apple platforms). */
        fun themeOf(context: Context): ThemeId =
            context.getSharedPreferences(THEME_PREFERENCES, Context.MODE_PRIVATE).getString(THEME_KEY, null)
                ?.let { saved -> ThemeId.entries.firstOrNull { it.name == saved } } ?: ThemeId.CLASSIC_CABLE

        suspend fun reload(context: Context) = WhatsOnWidget().updateAll(context)
    }
}

/** The widget's ▶: the next channel. */
class FlipForward : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        WhatsOnStore(context).apply { offset += 1 }
        WhatsOnWidget().update(context, glanceId)
    }
}

/** The widget's ◀: the previous channel. */
class FlipBack : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        WhatsOnStore(context).apply { offset -= 1 }
        WhatsOnWidget().update(context, glanceId)
    }
}

class WhatsOnWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = WhatsOnWidget()
}
