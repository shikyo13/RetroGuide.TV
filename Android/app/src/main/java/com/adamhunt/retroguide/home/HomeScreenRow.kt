package com.adamhunt.retroguide.home

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.tvprovider.media.tv.PreviewChannel
import androidx.tvprovider.media.tv.PreviewChannelHelper
import androidx.tvprovider.media.tv.PreviewProgram
import androidx.tvprovider.media.tv.TvContractCompat
import com.adamhunt.retroguide.R
import com.adamhunt.retroguide.core.HomeRowEntry
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.security.MessageDigest

/**
 * "What's On" on the TV's home screen (the Apple app's Top Shelf): a row of
 * channels with what's on each, opening the app on that channel. Android TV
 * launchers that show app rows display it; Google TV keeps its own rows.
 */
class HomeScreenRow(private val context: Context) {
    private object Saved {
        const val PREFERENCES = "homeRow"
        const val CHANNEL_ID = "channelID"
    }

    private object Row {
        const val NAME = "What's On"
        const val APP_LINK = "retroguide://channel"
        const val CHANNEL_LINK = "retroguide://channel?id="
        const val DIGEST = "SHA-256"
    }

    private val helper = PreviewChannelHelper(context)
    private val preferences = context.getSharedPreferences(Saved.PREFERENCES, Context.MODE_PRIVATE)
    private val http = OkHttpClient()
    private val folder = File(context.cacheDir, HomeArtworkProvider.FOLDER)

    /** Replaces the row's programs with [entries] (on a background thread). */
    suspend fun update(entries: List<HomeRowEntry>) = withContext(Dispatchers.IO) {
        runCatching {
            val channelID = channelID() ?: return@runCatching
            context.contentResolver.delete(TvContractCompat.buildPreviewProgramsUriForChannel(channelID), null, null)
            folder.mkdirs()
            val kept = mutableSetOf<String>()
            for ((weight, entry) in entries.withIndex()) {
                val art = entry.program?.artwork?.let { it.thumbnail ?: it.backdrop }?.let(::download)
                art?.let { kept += it.name }
                val program = PreviewProgram.Builder()
                    .setChannelId(channelID)
                    .setType(TvContractCompat.PreviewPrograms.TYPE_CHANNEL)
                    .setTitle("${entry.number} · ${entry.name}")
                    .setDescription(entry.program?.let { listOfNotNull(it.headline, it.subheadline).joinToString(" · ") } ?: "")
                    .setPosterArtAspectRatio(TvContractCompat.PreviewPrograms.ASPECT_RATIO_16_9)
                    .setPosterArtUri(art?.let(HomeArtworkProvider::uri))
                    .setIntentUri(Uri.parse(Row.CHANNEL_LINK + Uri.encode(entry.channelID)))
                    .setLive(true)
                    .setInternalProviderId(entry.channelID)
                    .setWeight(entries.size - weight)
                    .build()
                helper.publishPreviewProgram(program)
            }
            // Pictures no longer on the row.
            folder.listFiles()?.filter { it.name !in kept }?.forEach(File::delete)
        }
    }

    /** The row's id in the TV provider, publishing it the first time (or again if the launcher removed it). */
    private fun channelID(): Long? {
        val saved = preferences.getLong(Saved.CHANNEL_ID, -1)
        if (saved >= 0 && helper.getPreviewChannel(saved) != null) return saved
        val logo = BitmapFactory.decodeResource(context.resources, R.drawable.banner)
        val channel = PreviewChannel.Builder()
            .setDisplayName(Row.NAME)
            .setAppLinkIntentUri(Uri.parse(Row.APP_LINK))
            .setLogo(logo)
            .build()
        val id = runCatching { helper.publishDefaultChannel(channel) }.getOrNull() ?: return null
        preferences.edit().putLong(Saved.CHANNEL_ID, id).apply()
        return id
    }

    /** Downloads a picture to the shared folder, named for its address (without exposing it). */
    private fun download(url: String): File? = runCatching {
        val name = MessageDigest.getInstance(Row.DIGEST).digest(url.toByteArray()).joinToString("") { "%02x".format(it) } + ".jpg"
        val file = File(folder, name)
        if (!file.exists()) {
            http.newCall(Request.Builder().url(url).build()).execute().use { response ->
                check(response.isSuccessful)
                file.outputStream().use { response.body.byteStream().copyTo(it) }
            }
        }
        file
    }.getOrNull()
}
