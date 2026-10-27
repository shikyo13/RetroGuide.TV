package com.adamhunt.retroguide.core

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.nullable
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/** A request the core answered with an error. */
class CoreException(message: String) : Exception(message)

/**
 * Typed access to the Swift core. Each call blocks an IO-dispatcher thread
 * until the core answers; the core runs requests concurrently (a progress
 * check is answered while a refresh waits on the network).
 */
class CoreClient {
    private val json = Json { ignoreUnknownKeys = true; explicitNulls = false; encodeDefaults = true }

    @Serializable
    private data class StartParams(
        val filesDirectory: String,
        val resourcesDirectory: String,
        val installID: String,
        val deviceName: String,
        val appVersion: String,
        val osVersion: String,
        val tokens: Map<String, String>,
    )

    @Serializable private data class ServerParams(val serverID: String)
    @Serializable data class DevelopmentServer(
        val id: String,
        val kind: String,
        val name: String,
        val address: String,
        val token: String,
        val userID: String? = null,
        val accountToken: String? = null,
    )
    @Serializable private data class LibrarySelectionParams(val serverID: String, val libraryIDs: List<String>)
    @Serializable private data class LinkParams(val id: Int)
    @Serializable private data class IdsParams(val ids: List<String>)
    @Serializable private data class AddressParams(val address: String)
    @Serializable private data class SignInParams(val username: String, val password: String)
    @Serializable private data class GuideParams(val from: Double, val to: Double, val channelIDs: List<String>? = null)
    @Serializable private data class TuneParams(
        val channelID: String,
        val generation: Int,
        val programID: String? = null,
        val position: Double? = null,
    )
    @Serializable private data class PlaybackEventParams(val event: String, val generation: Int, val position: Double? = null)
    @Serializable private data class ChannelParams(val channelID: String)
    @Serializable private data class TrackChoiceParams(val kind: String, val optionID: String?, val scope: String?)
    @Serializable private data class SubtitleNudgeParams(val direction: Int, val repeatCount: Int)
    @Serializable private data class OrderingParams(val channelID: String, val ordering: String)
    @Serializable private data class TitleParams(val channelID: String, val showID: String)
    @Serializable private data class HiddenParams(val channelID: String, val isHidden: Boolean)
    @Serializable private data class EnabledParams(val isEnabled: Boolean)
    @Serializable private data class SearchParams(val query: String)
    @Serializable private data class SourceParams(val source: String, val isEnabled: Boolean)
    @Serializable private data class ValueParams(val value: String?)
    @Serializable private data class PlaybackParams(val serverID: String, val quality: String? = null, val extraBuffering: Boolean? = null)
    @Serializable private data class ConnectionParams(val serverID: String, val preference: String, val address: String? = null)
    @Serializable private data class ServerAddressParams(val serverID: String, val address: String)
    @Serializable private data class ReachabilityParams(val isVPNActive: Boolean)
    @Serializable private data class LockedParams(val isLocked: Boolean)
    @Serializable private data class ReminderParams(val channelID: String, val programID: String)
    @Serializable private data class ReminderIDParams(val id: String)
    @Serializable private data class ParentalChannelParams(val channel: ChannelDraft, val policy: ParentalDraft)
    @Serializable private data class TrackCommandParams(val selection: SelectionInfo, val trackList: String)
    @Serializable private data class EndStreamParams(val serverID: String, val sessionID: String)
    @Serializable private class NoParams

    suspend fun start(
        filesDirectory: String,
        resourcesDirectory: String,
        installID: String,
        deviceName: String,
        appVersion: String,
        osVersion: String,
        tokens: Map<String, String>,
    ): StartResult = call(
        "start",
        StartParams(filesDirectory, resourcesDirectory, installID, deviceName, appVersion, osVersion, tokens),
        StartParams.serializer(), StartResult.serializer(),
    )

    suspend fun servers() = call("servers", ListSerializer(ServerInfo.serializer()))
    /** Debug builds only: a server with a known address and token, as the Apple app's DEBUG bootstrap adds. */
    suspend fun addDevelopmentServer(server: DevelopmentServer) =
        call("server.addDevelopment", server, DevelopmentServer.serializer(), ServersChange.serializer())

    suspend fun removeServer(serverID: String) =
        call("server.remove", ServerParams(serverID), ServerParams.serializer(), ServersChange.serializer())
    suspend fun libraries(serverID: String) =
        call("libraries", ServerParams(serverID), ServerParams.serializer(), ListSerializer(LibraryInfo.serializer()))
    suspend fun selectLibraries(serverID: String, libraryIDs: List<String>) = call(
        "libraries.select", LibrarySelectionParams(serverID, libraryIDs), LibrarySelectionParams.serializer(), JsonElement.serializer(),
    )

    suspend fun plexLinkCode() = call("plex.linkCode", LinkCode.serializer())
    suspend fun checkPlexLink(id: Int) = call("plex.checkLink", LinkParams(id), LinkParams.serializer(), LinkStatus.serializer())
    suspend fun plexServers() = call("plex.servers", ListSerializer(PlexServerOption.serializer()))
    suspend fun addPlexServers(ids: List<String>) =
        call("plex.addServers", IdsParams(ids), IdsParams.serializer(), ServersChange.serializer())

    suspend fun findJellyfin(address: String) =
        call("jellyfin.find", AddressParams(address), AddressParams.serializer(), JellyfinServerOption.serializer())
    suspend fun startQuickConnect() = call("jellyfin.quickConnect", QuickConnectInfo.serializer())
    suspend fun checkQuickConnect() = call("jellyfin.checkQuickConnect", QuickConnectStatus.serializer())
    suspend fun signInJellyfin(username: String, password: String) =
        call("jellyfin.signIn", SignInParams(username, password), SignInParams.serializer(), ServersChange.serializer())

    suspend fun refresh() = call("refresh", RefreshResult.serializer())
    suspend fun progress() = call("progress", ProgressInfo.serializer())
    suspend fun channels() = call("channels", ListSerializer(ChannelInfo.serializer()))
    suspend fun guide(from: Double, to: Double, channelIDs: List<String>? = null) = call(
        "guide", GuideParams(from, to, channelIDs), GuideParams.serializer(), ListSerializer(GuideRow.serializer()),
    )
    /** [programID]: watch that program from [position] (the start) instead of live. */
    suspend fun tune(channelID: String, generation: Int, programID: String? = null, position: Double? = null) =
        call("tune", TuneParams(channelID, generation, programID, position), TuneParams.serializer(), TuneResult.serializer())

    /** `started`, `progress`, `paused`, `resumed` or `stopped`, for servers that track playback. */
    suspend fun playbackEvent(event: String, generation: Int, position: Double?) = call(
        "playback.event", PlaybackEventParams(event, generation, position), PlaybackEventParams.serializer(), JsonElement.serializer(),
    )

    suspend fun options(channelID: String) =
        call("options", ChannelParams(channelID), ChannelParams.serializer(), OptionsInfo.serializer())
    /** [scope] `null`: back to automatic. [optionID] `null` with subtitles: off. */
    suspend fun chooseTrack(kind: String, optionID: String?, scope: String?) = call(
        "tracks.choose", TrackChoiceParams(kind, optionID, scope), TrackChoiceParams.serializer(), TrackState.serializer().nullable,
    )
    suspend fun nudgeSubtitles(direction: Int, repeatCount: Int) = call(
        "subtitles.nudge", SubtitleNudgeParams(direction, repeatCount), SubtitleNudgeParams.serializer(), TrackState.serializer().nullable,
    )

    suspend fun setOrdering(channelID: String, ordering: String) =
        call("channel.setOrdering", OrderingParams(channelID, ordering), OrderingParams.serializer(), ListSerializer(ChannelInfo.serializer()))
    suspend fun removeTitle(channelID: String, showID: String) =
        call("channel.removeTitle", TitleParams(channelID, showID), TitleParams.serializer(), ListSerializer(ChannelInfo.serializer()))
    suspend fun restoreTitle(channelID: String, showID: String) =
        call("channel.restoreTitle", TitleParams(channelID, showID), TitleParams.serializer(), ListSerializer(ChannelInfo.serializer()))
    suspend fun setHidden(channelID: String, isHidden: Boolean) =
        call("channel.setHidden", HiddenParams(channelID, isHidden), HiddenParams.serializer(), ListSerializer(ChannelInfo.serializer()))
    suspend fun toggleFavorite(channelID: String) =
        call("favorites.toggle", ChannelParams(channelID), ChannelParams.serializer(), ListSerializer(ChannelInfo.serializer()))
    suspend fun viewing() = call("viewing", ViewingInfo.serializer())
    suspend fun setFavoritesOnly(isEnabled: Boolean) =
        call("viewing.favoritesOnly", EnabledParams(isEnabled), EnabledParams.serializer(), ViewingInfo.serializer())
    suspend fun setPro(isEnabled: Boolean) =
        call("pro.set", EnabledParams(isEnabled), EnabledParams.serializer(), JsonElement.serializer())
    suspend fun search(query: String) =
        call("search", SearchParams(query), SearchParams.serializer(), ListSerializer(SearchHit.serializer()))
    suspend fun trackCommands(selection: SelectionInfo, trackList: String) = call(
        "trackCommands", TrackCommandParams(selection, trackList), TrackCommandParams.serializer(),
        ListSerializer(ListSerializer(String.serializer())),
    )
    suspend fun endStream(serverID: String, sessionID: String) = call(
        "endStream", EndStreamParams(serverID, sessionID), EndStreamParams.serializer(), JsonElement.serializer(),
    )

    // Settings › Servers

    suspend fun serverDetail(serverID: String) =
        call("server.detail", ServerParams(serverID), ServerParams.serializer(), ServerDetail.serializer())
    suspend fun setPlayback(serverID: String, quality: String? = null, extraBuffering: Boolean? = null) = call(
        "server.setPlayback", PlaybackParams(serverID, quality, extraBuffering), PlaybackParams.serializer(), ServerDetail.serializer(),
    )
    /** [address]: what the viewer typed, for a custom address. */
    suspend fun setConnection(serverID: String, preference: String, address: String? = null) = call(
        "server.setConnection", ConnectionParams(serverID, preference, address), ConnectionParams.serializer(), ConnectionResult.serializer(),
    )
    suspend fun setJellyfinAddress(serverID: String, address: String) = call(
        "server.setJellyfinAddress", ServerAddressParams(serverID, address), ServerAddressParams.serializer(), ConnectionResult.serializer(),
    )
    suspend fun checkReachability(isVPNActive: Boolean) = call(
        "servers.checkReachability", ReachabilityParams(isVPNActive), ReachabilityParams.serializer(), ReachabilityResult.serializer(),
    )

    // The TV's home screen row

    suspend fun homeRow() = call("homeRow", ListSerializer(HomeRowEntry.serializer()))
    suspend fun homeRowSettings() = call("homeRow.settings", HomeRowSettings.serializer())
    suspend fun setHomeRowFavorites(isEnabled: Boolean) =
        call("homeRow.favorites", EnabledParams(isEnabled), EnabledParams.serializer(), HomeRowSettings.serializer())

    // Program reminders

    suspend fun reminders() = call("reminders", RemindersState.serializer())
    suspend fun toggleReminder(channelID: String, programID: String) =
        call("reminders.toggle", ReminderParams(channelID, programID), ReminderParams.serializer(), RemindersState.serializer())
    suspend fun removeReminder(id: String) =
        call("reminders.remove", ReminderIDParams(id), ReminderIDParams.serializer(), RemindersState.serializer())
    suspend fun checkReminders() = call("reminders.check", RemindersState.serializer())

    // Settings › Parental Controls

    suspend fun parentalStatus() = call("parental.status", ParentalStatus.serializer())
    suspend fun setParentalLocked(isLocked: Boolean) =
        call("parental.setLocked", LockedParams(isLocked), LockedParams.serializer(), JsonElement.serializer())
    suspend fun parentalEditor() = call("parental.editor", ParentalEditor.serializer())
    suspend fun saveParental(draft: ParentalDraft) =
        call("parental.save", draft, ParentalDraft.serializer(), ListSerializer(ChannelInfo.serializer()))
    suspend fun previewParentalChannel(channel: ChannelDraft, policy: ParentalDraft) = call(
        "parental.previewChannel", ParentalChannelParams(channel, policy), ParentalChannelParams.serializer(), ChannelPreview.serializer(),
    )

    // Settings › Channels

    private val channelList = ListSerializer(ChannelInfo.serializer())

    suspend fun lineupSettings() = call("lineup.settings", LineupSettings.serializer())
    suspend fun manageChannels() = call("lineup.channels", ListSerializer(ChannelSummary.serializer()))
    suspend fun setSource(source: String, isEnabled: Boolean) =
        call("lineup.setSource", SourceParams(source, isEnabled), SourceParams.serializer(), channelList)
    suspend fun setSimulcastLimit(limit: String) = call("lineup.simulcastLimit", ValueParams(limit), ValueParams.serializer(), channelList)
    /** [ordering] `null`: each channel's own. */
    suspend fun setOrderingForAllChannels(ordering: String?) =
        call("lineup.orderingAll", ValueParams(ordering), ValueParams.serializer(), channelList)
    suspend fun setScheduleGrid(grid: String) = call("lineup.scheduleGrid", ValueParams(grid), ValueParams.serializer(), channelList)
    suspend fun removedTitles() = call("lineup.removedTitles", ListSerializer(RemovedGroup.serializer()))
    suspend fun channelDetail(channelID: String) =
        call("channel.detail", ChannelParams(channelID), ChannelParams.serializer(), ChannelDetail.serializer())
    suspend fun channelFacets() = call("customChannel.facets", ChannelFacets.serializer())
    suspend fun previewChannel(draft: ChannelDraft) =
        call("customChannel.preview", draft, ChannelDraft.serializer(), ChannelPreview.serializer())
    suspend fun saveCustomChannel(draft: ChannelDraft) = call("customChannel.save", draft, ChannelDraft.serializer(), channelList)
    suspend fun deleteCustomChannel(channelID: String) =
        call("customChannel.delete", ChannelParams(channelID), ChannelParams.serializer(), channelList)

    private suspend fun <R> call(method: String, result: KSerializer<R>): R =
        call(method, NoParams(), NoParams.serializer(), result)

    private suspend fun <P, R> call(method: String, params: P, paramsSerializer: KSerializer<P>, result: KSerializer<R>): R =
        withContext(Dispatchers.IO) {
            val request = buildJsonObject {
                put("method", method)
                put("params", json.encodeToJsonElement(paramsSerializer, params))
            }
            val response = json.parseToJsonElement(NativeCore.call(request.toString())).jsonObject
            if (response["ok"]?.jsonPrimitive?.boolean != true) {
                throw CoreException((response["error"] as? JsonPrimitive)?.content ?: "The request failed.")
            }
            json.decodeFromJsonElement(result, response["result"] ?: JsonObject(emptyMap()))
        }
}
