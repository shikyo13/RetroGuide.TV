package com.adamhunt.retroguide.core

import kotlinx.serialization.Serializable

// Mirrors of the Swift core's request results (Android/core/Sources/RetroGuideCore).
// Dates are seconds since 1970.

@Serializable
data class ServerInfo(val id: String, val name: String, val kind: String, val address: String, val isOnline: Boolean)

@Serializable
data class StartResult(val servers: List<ServerInfo>, val channelCount: Int)

@Serializable
data class ServersChange(val servers: List<ServerInfo>, val tokens: Map<String, String>)

@Serializable
data class LibraryInfo(val id: String, val title: String, val kind: String, val isSelected: Boolean)

@Serializable
data class LinkCode(val id: Int, val code: String, val url: String)

@Serializable
data class LinkStatus(val isLinked: Boolean)

@Serializable
data class PlexServerOption(val id: String, val name: String, val isOwned: Boolean)

@Serializable
data class JellyfinServerOption(val id: String, val name: String, val address: String, val hasQuickConnect: Boolean)

@Serializable
data class QuickConnectInfo(val code: String)

@Serializable
data class QuickConnectStatus(val isApproved: Boolean, val change: ServersChange? = null)

@Serializable
data class RefreshResult(val channelCount: Int, val offlineServers: List<String>)

@Serializable
data class ProgressInfo(val fraction: Double, val message: String)

@Serializable
data class ChannelInfo(val id: String, val number: Int, val name: String, val callSign: String, val isHidden: Boolean)

@Serializable
data class GuideRow(val channelID: String, val programs: List<ProgramInfo>)

@Serializable
data class ProgramInfo(
    val id: String,
    val itemID: String,
    val showID: String,
    val kind: String,
    val start: Double,
    val contentEnd: Double,
    val end: Double,
    val headline: String,
    val subheadline: String? = null,
    val title: String,
    val year: Int? = null,
    val contentRating: String? = null,
    val audience: String = "unrated",
    val summary: String? = null,
    val artwork: ArtworkInfo,
)

@Serializable
data class ArtworkInfo(
    val poster: String? = null,
    val backdrop: String? = null,
    val logo: String? = null,
    val thumbnail: String? = null,
)

@Serializable
data class TuneResult(
    val channelID: String,
    val program: ProgramInfo,
    val intermissionUntil: Double? = null,
    val stream: StreamInfo? = null,
    val tracks: TracksInfo? = null,
)

@Serializable
data class StreamInfo(
    val url: String,
    val position: Double,
    val serverID: String,
    val sessionID: String,
    val needsTeardown: Boolean,
    val maxBytes: String,
    val readaheadSeconds: String,
)

@Serializable
data class TracksInfo(val audio: List<TrackInfo>, val subtitles: List<TrackInfo>, val selection: SelectionInfo)

@Serializable
data class TrackInfo(
    val id: String,
    val title: String,
    val language: String? = null,
    val isForced: Boolean,
    val streamIndex: Int? = null,
    val url: String? = null,
)

@Serializable
data class SelectionInfo(
    val audioStreamIndex: Int? = null,
    val subtitle: String,
    val subtitleStreamIndex: Int? = null,
    val subtitleURL: String? = null,
) {
    companion object {
        const val NONE = "none"
        const val EMBEDDED = "embedded"
        const val EXTERNAL = "external"
    }

    fun withAudio(track: TrackInfo) = copy(audioStreamIndex = track.streamIndex)

    fun withSubtitle(track: TrackInfo?) = when {
        track == null -> copy(subtitle = NONE, subtitleStreamIndex = null, subtitleURL = null)
        track.url != null -> copy(subtitle = EXTERNAL, subtitleStreamIndex = null, subtitleURL = track.url)
        else -> copy(subtitle = EMBEDDED, subtitleStreamIndex = track.streamIndex, subtitleURL = null)
    }
}
