package com.adamhunt.retroguide.widget

import android.content.Context
import com.adamhunt.retroguide.core.WidgetSnapshot
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.security.MessageDigest

/**
 * The widget's saved guide (the Apple app's `WhatsOnStore`): the snapshot as
 * JSON plus artwork files, in the app's private storage. Server image
 * addresses carry access tokens, so only downloaded files reach the widget.
 */
class WhatsOnStore(private val context: Context) {
    /** A program as the widget draws it: artwork as local files. */
    @Serializable
    data class Program(
        val title: String,
        val episode: String? = null,
        val start: Double,
        val end: Double,
        val stillFile: String? = null,
        val logoFile: String? = null,
    )

    @Serializable
    data class Channel(val id: String, val number: Int, val name: String, val callSign: String, val programs: List<Program>) {
        fun programAt(time: Double) = programs.firstOrNull { time >= it.start && time < it.end }
    }

    @Serializable
    data class Saved(val channels: List<Channel>, val pinned: Boolean)

    private object Files {
        const val SNAPSHOT = "whats-on.json"
        const val ARTWORK = "whats-on-artwork"
        const val OFFSET = "whatsOnOffset"
        const val PREFERENCES = "whatsOn"
        const val DIGEST = "SHA-256"
        /** Artwork is fetched for this many programs per channel (the ones on soonest). */
        const val ARTWORK_PROGRAMS = 3
    }

    private val json = Json { ignoreUnknownKeys = true }
    private val folder = File(context.filesDir, Files.ARTWORK)
    private val preferences = context.getSharedPreferences(Files.PREFERENCES, Context.MODE_PRIVATE)

    fun load(): Saved? = runCatching {
        json.decodeFromString(Saved.serializer(), File(context.filesDir, Files.SNAPSHOT).readText())
    }.getOrNull()

    /** Saves [snapshot], downloading artwork for each channel's next programs. Runs on a background thread. */
    fun save(snapshot: WidgetSnapshot, http: OkHttpClient) {
        folder.mkdirs()
        val kept = mutableSetOf<String>()
        val saved = Saved(snapshot.channels.map { channel ->
            Channel(channel.id, channel.number, channel.name, channel.callSign, channel.programs.mapIndexed { index, program ->
                val wantsArt = index < Files.ARTWORK_PROGRAMS
                val still = if (wantsArt) (program.still ?: program.backdrop)?.let { download(it, http) } else null
                val logo = if (wantsArt) program.logo?.let { download(it, http) } else null
                listOfNotNull(still, logo).forEach { kept += it }
                Program(program.title, program.episode, program.start, program.end, still, logo)
            })
        }, snapshot.pinned)
        val temporary = File(context.filesDir, "${Files.SNAPSHOT}.tmp")
        temporary.writeText(json.encodeToString(Saved.serializer(), saved))
        temporary.renameTo(File(context.filesDir, Files.SNAPSHOT))
        folder.listFiles()?.filter { it.name !in kept }?.forEach(File::delete)
    }

    fun clear() {
        File(context.filesDir, Files.SNAPSHOT).delete()
        folder.listFiles()?.forEach(File::delete)
    }

    fun artwork(name: String?): File? = name?.let { File(folder, it) }?.takeIf(File::exists)

    /** Which channel the flip buttons have moved to. */
    var offset: Int
        get() = preferences.getInt(Files.OFFSET, 0)
        set(value) = preferences.edit().putInt(Files.OFFSET, value).apply()

    private fun download(url: String, http: OkHttpClient): String? = runCatching {
        val name = MessageDigest.getInstance(Files.DIGEST).digest(url.toByteArray()).joinToString("") { "%02x".format(it) } + ".jpg"
        val file = File(folder, name)
        if (!file.exists()) {
            http.newCall(Request.Builder().url(url).build()).execute().use { response ->
                check(response.isSuccessful)
                file.outputStream().use { response.body.byteStream().copyTo(it) }
            }
        }
        name
    }.getOrNull()
}
