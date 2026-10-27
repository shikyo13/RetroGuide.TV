package com.adamhunt.retroguide.core

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
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
    private val json = Json { ignoreUnknownKeys = true; explicitNulls = false }

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
    @Serializable private data class TuneParams(val channelID: String)
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
    suspend fun tune(channelID: String) = call("tune", TuneParams(channelID), TuneParams.serializer(), TuneResult.serializer())
    suspend fun trackCommands(selection: SelectionInfo, trackList: String) = call(
        "trackCommands", TrackCommandParams(selection, trackList), TrackCommandParams.serializer(),
        ListSerializer(ListSerializer(String.serializer())),
    )
    suspend fun endStream(serverID: String, sessionID: String) = call(
        "endStream", EndStreamParams(serverID, sessionID), EndStreamParams.serializer(), JsonElement.serializer(),
    )

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
