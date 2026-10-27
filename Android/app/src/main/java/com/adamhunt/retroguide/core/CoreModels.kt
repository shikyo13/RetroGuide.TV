package com.adamhunt.retroguide.core

import kotlinx.serialization.Serializable

// Mirrors of the Swift core's request results (Android/core/Sources/RetroGuideCore).
// Dates are seconds since 1970.

@Serializable
data class ServerInfo(val id: String, val name: String, val kind: String, val address: String, val isOnline: Boolean)

@Serializable
data class StartResult(val servers: List<ServerInfo>, val channelCount: Int, val oldestRefresh: Double? = null)

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
data class ChannelInfo(
    val id: String,
    val number: Int,
    val name: String,
    val callSign: String,
    val isHidden: Boolean,
    val isFavorite: Boolean = false,
    /** `ChannelSource`: curated, decade, series, library, custom, … */
    val source: String = "",
)

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
    val trackState: TrackState? = null,
)

/** The viewer's choices for what's on: scopes are `null` when automatic. */
@Serializable
data class TrackState(
    val selection: SelectionInfo? = null,
    val audioScope: String? = null,
    val subtitleScope: String? = null,
    val subtitleDelay: Double = 0.0,
    val subtitleDelayText: String = "",
)

@Serializable
data class Choice(val id: String, val title: String)

/** Everything the Options panel shows for what's on. */
@Serializable
data class OptionsInfo(
    val headline: String,
    val channelID: String,
    val channelTitle: String,
    val isFavorite: Boolean,
    val scopes: List<Choice>,
    val ordering: String,
    val orderings: List<Choice>,
    val orderingExplanation: String,
    val canChangeOrdering: Boolean,
    val placement: String,
    val isRemovable: Boolean,
    val canRemove: Boolean,
    val showID: String,
    val isMovie: Boolean,
)

@Serializable
data class ViewingInfo(val favoritesOnly: Boolean)

@Serializable
data class SearchHit(
    val id: String,
    val title: String,
    val kind: String,
    val poster: String? = null,
    val channelID: String? = null,
    val channelNumber: Int? = null,
    val channelName: String? = null,
    val callSign: String? = null,
    val airing: ProgramInfo? = null,
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

// Settings › Channels

@Serializable
data class Described(val id: String, val title: String, val detail: String)

@Serializable
data class ChannelGroup(val id: String, val name: String, val isEnabled: Boolean, val channelCount: Int)

@Serializable
data class LineupSettings(
    val channelCount: Int,
    val hiddenCount: Int,
    val favoriteCount: Int,
    val removedTitleCount: Int,
    val simulcastLimit: String,
    val simulcastLimits: List<Described>,
    /** `null`: each channel's own order. */
    val defaultOrdering: String? = null,
    val orderings: List<Described>,
    val scheduleGrid: String,
    val scheduleGrids: List<Choice>,
    val groups: List<ChannelGroup>,
    val canCreateCustomChannel: Boolean,
    val canChangeScheduling: Boolean,
    val canAddServer: Boolean,
)

@Serializable
data class ChannelSummary(
    val id: String,
    val number: Int,
    val name: String,
    val isHidden: Boolean,
    val isFavorite: Boolean,
    val source: String,
    val sourceName: String,
    val size: String,
)

@Serializable
data class RemovedTitle(val showID: String, val name: String)

@Serializable
data class RemovedGroup(val channelID: String, val channelName: String, val titles: List<RemovedTitle>)

@Serializable
data class ChannelDetail(
    val channel: ChannelSummary,
    val featuring: List<String>,
    val ordering: String,
    val removedTitles: List<RemovedTitle>,
    val draft: ChannelDraft? = null,
)

/** A custom channel as the editor sees it; [id] is `null` for a new one. */
@Serializable
data class ChannelDraft(
    val id: String? = null,
    val name: String = "",
    val ordering: String = "blockShuffle",
    val kinds: List<String> = emptyList(),
    val categories: List<String> = emptyList(),
    val seriesIDs: List<String> = emptyList(),
    val networks: List<String> = emptyList(),
    val collections: List<String> = emptyList(),
    val decades: List<Int> = emptyList(),
    val audiences: List<String> = emptyList(),
    val libraryIDs: List<String> = emptyList(),
)

@Serializable
data class FacetOption(val id: String, val title: String, val detail: String? = null)

@Serializable
data class ChannelFacets(
    val kinds: List<FacetOption>,
    val categories: List<FacetOption>,
    val series: List<FacetOption>,
    val networks: List<FacetOption>,
    val collections: List<FacetOption>,
    val decades: List<FacetOption>,
    val audiences: List<FacetOption>,
    val libraries: List<FacetOption>,
)

@Serializable
data class ChannelPreview(val programCount: Int, val summary: String, val shows: List<String>)

// Settings › Servers

@Serializable
data class ServerDetail(
    val id: String,
    val name: String,
    val kind: String,
    val kindName: String,
    val isOffline: Boolean,
    val status: String,
    val quality: String,
    val qualities: List<Described>,
    val extraBuffering: Boolean,
    val connection: String,
    val connections: List<Described>,
    val customAddress: String? = null,
    val address: String,
)

@Serializable
data class ConnectionResult(val server: ServerDetail, val message: String? = null)

@Serializable
data class ReachabilityResult(val changed: Boolean)

// Settings › Parental Controls

@Serializable
data class ParentalDraft(
    val isEnabled: Boolean = false,
    val usesCustomLineup: Boolean = false,
    val customChannels: List<ChannelDraft> = emptyList(),
    val maximumMovieRating: String = "PG",
    val maximumTVRating: String = "TV-PG",
    val allowsUnrated: Boolean = false,
    val allLibraries: Boolean = true,
    val libraryIDs: List<String> = emptyList(),
    val allGenres: Boolean = true,
    val genreNames: List<String> = emptyList(),
    val selectedContentOnly: Boolean = false,
    val collectionNames: List<String> = emptyList(),
    val allowedTitleIDs: List<String> = emptyList(),
    val blockedTitleIDs: List<String> = emptyList(),
)

@Serializable
data class ParentalEditor(
    val draft: ParentalDraft,
    val movieRatings: List<String>,
    val tvRatings: List<String>,
    val libraries: List<FacetOption>,
    val genres: List<FacetOption>,
    val collections: List<FacetOption>,
    val titles: List<FacetOption>,
)

@Serializable
data class ParentalStatus(val isEnabled: Boolean, val usesCustomLineup: Boolean)

// Program reminders

@Serializable
data class ReminderInfo(val id: String, val channelID: String, val title: String, val channelName: String, val start: Double)

@Serializable
data class RemindersState(val pending: List<ReminderInfo>, val message: String? = null, val due: ReminderInfo? = null)

// The TV's home screen row

@Serializable
data class HomeRowEntry(val channelID: String, val number: Int, val name: String, val program: ProgramInfo? = null)

@Serializable
data class HomeRowSettings(val usesFavorites: Boolean, val hasFavorites: Boolean)
